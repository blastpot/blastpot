//               ,--,                                   ,----,                                 ,----,
//            ,---.'|                                 ,/   .`|,-.----.       ,----..         ,/   .`|
//     ,---,. |   | :      ,---,       .--.--.      ,`   .'  :\    /  \     /   /   \      ,`   .'  :
//   ,'  .'  \:   : |     '  .' \     /  /    '.  ;    ;     /|   :    \   /   .     :   ;    ;     /
// ,---.' .' ||   ' :    /  ;    '.  |  :  /`. /.'___,/    ,' |   |  .\ : .   /   ;.  \.'___,/    ,'
// |   |  |: |;   ; '   :  :       \ ;  |  |--` |    :     |  .   :  |: |.   ;   /  ` ;|    :     |
// :   :  :  /'   | |__ :  |   /\   \|  :  ;_   ;    |.';  ;  |   |   \ :;   |  ; \ ; |;    |.';  ;
// :   |    ; |   | :.'||  :  ' ;.   :\  \    `.`----'  |  |  |   : .   /|   :  | ; | '`----'  |  |
// |   :     \'   :    ;|  |  ;/  \   \`----.   \   '   :  ;  ;   | |`-' .   |  ' ' ' :    '   :  ;
// |   |   . ||   |  ./ '  :  | \  \ ,'__ \  \  |   |   |  '  |   | ;    '   ;  \; /  |    |   |  '
// '   :  '; |;   : ;   |  |  '  '--' /  /`--'  /   '   :  |  :   ' |     \   \  ',  /     '   :  |
// |   |  | ; |   ,/    |  :  :      '--'.     /    ;   |.'   :   : :      ;   :    /      ;   |.'
// |   :   /  '---'     |  | ,'        `--'---'     '---'     |   | :       \   \ .'       '---'
// |   | ,'             `--''                                 `---'.|        `---`
// `----'                                                       `---`

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEntropy} from "entropy/IEntropy.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {IBlast} from "./interfaces/IBlast.sol";
import {IERC20} from "./interfaces/IERC20.sol";

error BidTooLow();
error BidTooHigh();
error IterationIsNotOver();
error InsufficientEntropyFee();
error EntropyAlreadyRequested();
error EntropyNotRequested();

/// @title Blastpot - a roullete-style contract that leverages
///         the entropy of the PYTH network for provable fairness.
///
/// @author Pluto (@homeslashpluto)
contract Blastpot is Owned, ReentrancyGuard {
    address public blastYieldManager;
    address public entropy;

    address public immutable TOKEN;
    uint256 public immutable RAKE;
    uint256 public immutable START_BLOCK;
    uint256 public immutable BLOCK_INTERVAL;
    uint256 public immutable MIN_BID;
    uint256 public immutable MAX_BID;

    uint256 public iteration;

    struct EntropyRequest {
        bool requested;
        uint64 sequenceNumber;
        address provider;
        address caller;
    }

    mapping(uint256 => EntropyRequest) public requests;

    struct BidRange {
        address bidder;
        uint256 min;
        uint256 max;
    }

    mapping(uint256 => BidRange[]) public bidRanges;

    uint256 public accruedRake;

    event Bid(uint256 indexed iteration, address indexed bidder, uint256 amount);
    event EntropyRequested(uint256 indexed iteration, address provider, uint64 sequenceNumber);
    event Winner(uint256 indexed iteration, address indexed winner, uint256 amount, uint256 rake);

    constructor(
        address _owner,
        address _blastYieldManager,
        address _entropy,
        address _token,
        uint256 _rake,
        uint256 _blockInterval,
        uint256 _minBid,
        uint256 _maxBid
    ) Owned(_owner) {
        blastYieldManager = _blastYieldManager;

        entropy = _entropy;

        TOKEN = _token;
        RAKE = _rake;
        START_BLOCK = block.number;
        BLOCK_INTERVAL = _blockInterval;
        MIN_BID = _minBid;
        MAX_BID = _maxBid;

        IBlast(blastYieldManager).configureClaimableYield();
    }

    /// @notice Update the address of the BlastYieldManager contract
    function updateBlastYieldManagement(address _blastYieldManager) external nonReentrant onlyOwner {
        blastYieldManager = _blastYieldManager;
        IBlast(blastYieldManager).configureClaimableYield();
    }

    /// @notice Update the address of the Entropy contract
    function updateEntropy(address _entropy) external onlyOwner {
        entropy = _entropy;
    }

    /// @notice Claim all yield from the BlastYieldManager contract
    function claimYield(address _recipient) external nonReentrant onlyOwner {
        IBlast(blastYieldManager).claimAllYield(address(this), _recipient);
    }

    /// @notice Claim all gas from the BlastYieldManager contract
    function claimGas(address _recipient) external nonReentrant onlyOwner {
        IBlast(blastYieldManager).claimAllGas(address(this), _recipient);
    }

    /// @notice Claim fees generated from rake
    function claimRake(address _recipient) external nonReentrant onlyOwner {
        accruedRake = 0;
        uint256 _rake = accruedRake;
        IERC20(TOKEN).transfer(_recipient, _rake);
    }

    /// @notice bidRangeMax returns the liquidity for the iteration
    function bidRangeMax(uint256 _iteration) public view returns (uint256) {
        BidRange[] memory range = bidRanges[_iteration];
        if (range.length == 0) {
            return 0;
        }
        return range[range.length - 1].max;
    }

    /// @notice bid allows users to place a bid for the current iteration
    /// @notice msg.sender must approve this contract to transfer the amount of tokens
    /// @param _bidder delegated bidder
    /// @param _amount amount of tokens to bid; withdrawn from msg.sender
    /// @return bidIndex index of the bid in the bidRanges array for the current iteration
    function bid(address _bidder, uint256 _amount) external payable nonReentrant returns (uint256 bidIndex) {
        if (_amount < MIN_BID) revert BidTooLow();
        if (_amount > MAX_BID) revert BidTooHigh();

        uint256 currentIteration = (block.number - START_BLOCK) / BLOCK_INTERVAL;
        if (iteration != currentIteration) {
            iteration = currentIteration;
        }

        uint256 min = bidRangeMax(currentIteration);
        uint256 max = min + _amount;
        BidRange memory newRange = BidRange({min: min, max: max, bidder: _bidder});
        bidIndex = bidRanges[currentIteration].length;
        bidRanges[currentIteration].push(newRange);

        IERC20(TOKEN).transferFrom(msg.sender, address(this), _amount);

        emit Bid(currentIteration, _bidder, _amount);
    }

    /// @notice iterationEndBlock returns the block number at which the iteration ends
    function iterationEndBlock(uint256 _iteration) public view returns (uint256) {
        return START_BLOCK + (_iteration + 1) * BLOCK_INTERVAL;
    }

    /// @notice entropyFee returns the entropy provider and fee
    function entropyFee() external view returns (address provider, uint256 fee) {
        provider = IEntropy(entropy).getDefaultProvider();
        fee = IEntropy(entropy).getFee(provider);
    }

    /// @notice requestEntropy requests entropy from the Entropy contract
    /// @notice entropy must not have been requested for the iteration and the iteration must be over
    /// @notice must use the entropy fee and provider from above. No refunds are given for entropy fee overpayment
    /// @param provider address of the entropy provider
    /// @param _iteration iteration for which entropy is requested
    function requestEntropy(address provider, uint256 _iteration)
        external
        payable
        nonReentrant
        returns (EntropyRequest memory)
    {
        if (block.number < iterationEndBlock(_iteration)) revert IterationIsNotOver();
        if (requests[_iteration].requested) revert EntropyAlreadyRequested();

        if (provider == address(0)) {
            provider = IEntropy(entropy).getDefaultProvider();
        }
        uint256 fee = IEntropy(entropy).getFee(provider);
        if (msg.value < fee) revert InsufficientEntropyFee();

        uint64 sequenceNumber =
            IEntropy(entropy).request{value: fee}(provider, keccak256(abi.encodePacked(_iteration)), true);

        EntropyRequest memory request =
            EntropyRequest({requested: true, sequenceNumber: sequenceNumber, provider: provider, caller: msg.sender});
        requests[_iteration] = request;

        emit EntropyRequested(_iteration, provider, sequenceNumber);
        return request;
    }

    /// @param _iteration iteration to determine the winner
    /// @param _random random number to determine the winner
    /// @return _winner address of the winner
    function winner(uint256 _iteration, uint256 _random) public view returns (address _winner) {
        BidRange[] memory range = bidRanges[_iteration];
        if (range.length == 0) {
            return address(0);
        }

        uint256 winningValue = _random % range[range.length - 1].max;

        uint256 low = 0;
        uint256 high = range.length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            BidRange memory midBid = range[mid];
            if (winningValue < midBid.min) {
                high = mid;
            } else if (winningValue > midBid.max) {
                low = mid + 1;
            } else {
                _winner = midBid.bidder;
                break;
            }
        }
    }

    /// @notice revealWinner reveals the winner of the iteration
    /// @notice entropy must have been already requested
    /// @notice pays out the winner, and distributes gas collected between the entropy requester and revealer
    /// @param _iteration iteration to reveal the winner
    /// @param _random random number from the entropy provider
    /// @return potWinner address of the winner
    function revealWinner(uint256 _iteration, bytes32 _random) external nonReentrant returns (address potWinner) {
        if (block.number < iterationEndBlock(_iteration)) revert IterationIsNotOver();
        if (!requests[_iteration].requested) revert EntropyNotRequested();

        EntropyRequest memory request = requests[_iteration];
        bytes32 randomNumber = IEntropy(entropy).reveal(
            request.provider, request.sequenceNumber, keccak256(abi.encodePacked(_iteration)), _random
        );

        potWinner = winner(_iteration, uint256(randomNumber));
        uint256 winningAmount = bidRangeMax(iteration);

        uint256 winningRake = (winningAmount * RAKE) / 10000;
        accruedRake += winningRake;

        uint256 gas = IBlast(blastYieldManager).claimAllGas(address(this), address(this));
        (bool success,) = payable(msg.sender).call{value: (gas / 2)}("");
        (success,) = payable(request.caller).call{value: (gas / 2)}("");

        IERC20(TOKEN).transfer(potWinner, winningAmount - winningRake);

        emit Winner(_iteration, potWinner, winningAmount, winningRake);
    }

    /// @notice Catch-all function to return the state of the contract by iteration
    function iterationState(uint256 _iteration) external view returns (BidRange[] memory, EntropyRequest memory) {
        return (bidRanges[_iteration], requests[_iteration]);
    }

    /// @notice iterationBids returns the number of bids for the iteration
    function iterationBids(uint256 _iteration) external view returns (uint256) {
        return bidRanges[_iteration].length;
    }

    receive() external payable {}
}

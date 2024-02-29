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

import {IBlast} from "./interfaces/IBlast.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {IEntropy} from "entropy/IEntropy.sol";
import {RedBlackTreeLib} from "solady/utils/RedBlackTreeLib.sol";
import {YieldPotFlashloanReceiver} from "interfaces/FlashloanReceiver.sol";

error BidTooLow();
error BidTooHigh();
error IterationIsNotOver();
error IncorrectClosestBid();
error InsufficientEntropyFee();
error EntropyAlreadyRequested();
error EntropyNotRequested();
error InsufficientFlashloanRepayment();

/// @title BlastpotYield - A yield-bearing roullete-style contract that leverages
///         the entropy of the PYTH network for provable fairness.
///
/// @author Pluto (@homeslashpluto)
contract BlastpotYield is ReentrancyGuard, Owned {
    address public blastYieldManager;
    address public entropy;
    address public feeCollector;

    uint256 private constant MIN_BID = 0.01 ether;

    address public immutable TOKEN;
    uint256 public immutable RAKE;
    uint256 public immutable START_BLOCK;
    uint256 public immutable BLOCK_INTERVAL;
    uint256 public immutable FLASHLOAN_FEE;

    // Current iteration, incremented from 0
    uint256 public iteration;
    uint256 public liquidity;

    // iteration => commitment
    mapping(uint256 => EntropyRequest) public requests;

    // iteration => BidRanges
    RedBlackTreeLib.Tree public tree;

    mapping(uint256 => address) public userByDeposit;

    // iteration => yield
    mapping(uint256 => uint256) public yield;

    struct EntropyRequest {
        bool requested;
        uint64 sequenceNumber;
        address provider;
        address caller;
    }

    event Withdraw(uint256 indexed iteration, uint256 amount, address indexed user);
    event Bid(uint256 indexed iteration, address indexed bidder, uint256 amount);
    event EntropyRequested(uint256 indexed iteration, address provider, uint64 sequenceNumber);
    event Winner(uint256 indexed iteration, address indexed winner, uint256 amount);

    constructor(
        address _owner,
        uint256 _blockInterval,
        address _token,
        address _entropy,
        address _blast,
        uint256 _flashloanFee,
        address _feeCollector
    ) Owned(_owner) {
        START_BLOCK = block.number;
        BLOCK_INTERVAL = _blockInterval;
        TOKEN = _token;
        entropy = _entropy;
        blastYieldManager = _blast;
        FLASHLOAN_FEE = _flashloanFee;
        feeCollector = _feeCollector;
    }

    function updateBlastYieldManagement(address _blastYieldManager) external nonReentrant onlyOwner {
        blastYieldManager = _blastYieldManager;
        IBlast(blastYieldManager).configureClaimableYield();
    }

    function updateEntropy(address _entropy) external onlyOwner {
        entropy = _entropy;
    }

    function updateFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function entropyFee() external view returns (address provider, uint256 fee) {
        provider = IEntropy(entropy).getDefaultProvider();
        fee = IEntropy(entropy).getFee(provider);
    }

    function bid(address _bidder, uint256 _amount) external nonReentrant {
        if (_amount < MIN_BID) revert BidTooLow();

        uint256 currentIteration = (block.number - START_BLOCK) / BLOCK_INTERVAL;
        if (iteration != currentIteration) {
            yield[iteration] = IERC20(TOKEN).balanceOf(address(this)) - liquidity;
            iteration = currentIteration;
        }

        liquidity += _amount;

        RedBlackTreeLib.insert(tree, _amount);

        userByDeposit[_amount] = _bidder;

        IERC20(TOKEN).transferFrom(msg.sender, address(this), _amount);

        emit Bid(iteration, _bidder, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        liquidity -= _amount;

        RedBlackTreeLib.remove(tree, _amount);

        delete userByDeposit[_amount];

        IERC20(TOKEN).transfer(msg.sender, _amount);

        emit Withdraw(iteration, _amount, msg.sender);
    }

    function requestEntropy(uint256 _iteration) external payable nonReentrant returns (EntropyRequest memory) {
        if (block.number < iterationEndBlock(_iteration)) revert IterationIsNotOver();
        if (requests[_iteration].requested) revert EntropyAlreadyRequested();

        address provider = IEntropy(entropy).getDefaultProvider();
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

    function revealWinner(uint256 _iteration, bytes32 _random, uint256 _closestBid) external nonReentrant {
        if (block.number < iterationEndBlock(_iteration)) revert IterationIsNotOver();
        if (!requests[_iteration].requested) revert EntropyNotRequested();

        EntropyRequest memory request = requests[_iteration];
        bytes32 randomNumber = IEntropy(entropy).reveal(
            request.provider, request.sequenceNumber, keccak256(abi.encodePacked(_iteration)), _random
        );

        address _winner = winner(_closestBid, uint256(randomNumber));
        uint256 amount = yield[_iteration];

        uint256 gas = IBlast(blastYieldManager).claimAllGas(address(this), address(this));
        (bool success,) = payable(msg.sender).call{value: gas / 2}("");
        (success,) = payable(request.caller).call{value: gas / 2}("");

        IERC20(TOKEN).transfer(_winner, amount);

        emit Winner(_iteration, _winner, amount);
    }

    /// @param closestBid The the ceiling bid that is closest to the random number
    function winner(uint256 closestBid, uint256 random) public view returns (address _winner) {
        uint256 mod = random % liquidity;
        uint256 amount;

        bytes32 closestPtr = RedBlackTreeLib.find(tree, closestBid);
        bytes32 prev = RedBlackTreeLib.prev(closestPtr);
        if (prev == 0 && mod < closestBid) {
            _winner = userByDeposit[closestBid];
            return _winner;
        }
        bytes32 next = RedBlackTreeLib.next(closestPtr);
        while (next != 0) {
            amount += RedBlackTreeLib.value(next);
            next = RedBlackTreeLib.next(next);
        }

        uint256 upperBound = liquidity == amount ? amount : liquidity - amount;
        uint256 lowerBound = upperBound - closestBid;
        if (mod >= lowerBound && mod < upperBound) {
            _winner = userByDeposit[closestBid];
        } else {
            revert IncorrectClosestBid();
        }
    }

    function iterationEndBlock(uint256 _iteration) public view returns (uint256) {
        return START_BLOCK + (_iteration + 1) * BLOCK_INTERVAL;
    }

    function getBid(uint256 amount) external view returns (bytes32) {
        return RedBlackTreeLib.find(tree, amount);
    }

    function getAllBids() external view returns (uint256[] memory) {
        return RedBlackTreeLib.values(tree);
    }

    /// @param x any random number, the total of all bids before the closest bid to x will be less than x
    /// @return _bid closest bid to the given value
    /// @notice returns the closest bid to the given value
    /// @notice this function should be used in junction with `winner` to determine the winner
    function closestBidTo(uint256 x) external view returns (uint256 _bid) {
        uint256 rand = x % liquidity;
        uint256[] memory values = RedBlackTreeLib.values(tree);
        uint256 total = 0;
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
            if (total > rand) {
                return values[i];
            }
        }
        return values[values.length - 1];
    }

    function closestOpenBid(uint256 _bid) external view returns (uint256) {
        bytes32 ptr = RedBlackTreeLib.find(tree, _bid);
        while (ptr != 0) {
            _bid -= 1;
            ptr = RedBlackTreeLib.find(tree, _bid);
        }
        return _bid;
    }

    function flashloan(uint256 _amount, address _to) external nonReentrant {
        IERC20(TOKEN).transfer(_to, _amount);

        YieldPotFlashloanReceiver(_to).receiveLoan(_amount);

        uint256 balance = IERC20(TOKEN).balanceOf(address(this));
        uint256 newBalance = liquidity + _amount * FLASHLOAN_FEE / 10000;
        if (balance < newBalance) {
            revert InsufficientFlashloanRepayment();
        }
        if (balance > liquidity) {
            IERC20(TOKEN).transfer(feeCollector, balance - liquidity);
        }
    }

    function skim() external nonReentrant {
        uint256 balance = IERC20(TOKEN).balanceOf(address(this));
        IERC20(TOKEN).transfer(feeCollector, balance - liquidity);
    }

    receive() external payable {}
}

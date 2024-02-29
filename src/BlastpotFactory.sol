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

import {Owned} from "solmate/auth/Owned.sol";
import {Blastpot} from "./Blastpot.sol";
import {IBlast} from "interfaces/IBlast.sol";

error InvalidInterval();
error InvalidMinBid();
error InvalidMaxBid();
error PotAlreadyExists();
error DeploymentFailed();

/// @title BlastpotFactory
/// @notice BlastpotFactory manages the Blastpot roullete-style contract that leverages
///         the entropy of the PYTH network for provable fairness.
///
/// @author Pluto (@homeslashpluto)
contract BlastpotFactory is Owned {
    uint256 internal constant BIPS = 10000;
    uint256 public constant MIN_BLOCK_INTERVAL = 150; // 2 second blocks * 150 = 5 minutes

    uint256 public rake;
    address public blast;

    struct PotConfig {
        uint256 blockInterval;
        uint256 minBid;
        uint256 maxBid;
        address token;
    }

    address[] public pots;

    mapping(bytes32 => address) public potByHash;

    event NewPot(address indexed pot, PotConfig config);

    constructor(uint256 _rake, address _blast) Owned(msg.sender) {
        rake = _rake;
        blast = _blast;
    }

    function adjustRake(uint256 newRake) external onlyOwner {
        rake = newRake;
    }

    function updateBlast(address _blast) external onlyOwner {
        blast = _blast;
    }

    function claimGas(address to) external onlyOwner returns (uint256 gas) {
        gas = IBlast(blast).claimAllGas(address(this), to);
    }

    /// @notice Creates a new Blastpot contract
    /// @param blockInterval The number of blocks between iterations
    /// @param minBid The minimum bid amount
    /// @param maxBid The maximum bid amount
    /// @param token The token to bid with
    /// @param entropy The address of the PYTH entropy contract
    /// @return pot The address of the new Blastpot contract
    function newPot(uint256 blockInterval, uint256 minBid, uint256 maxBid, address token, address entropy)
        external
        onlyOwner
        returns (address pot)
    {
        if (blockInterval < MIN_BLOCK_INTERVAL) revert InvalidInterval();
        if (minBid == type(uint256).max || minBid == 0) revert InvalidMinBid();
        if (maxBid < minBid) revert InvalidMaxBid();

        PotConfig memory config =
            PotConfig({blockInterval: blockInterval, minBid: minBid, maxBid: maxBid, token: token});

        bytes memory bytecode = type(Blastpot).creationCode;
        bytes32 salt = potHash(blockInterval, minBid, maxBid, token);

        if (potByHash[salt] != address(0)) revert PotAlreadyExists();

        address _owner = owner;
        uint256 _rake = rake;
        address _blast = blast;
        assembly {
            let size := add(mload(bytecode), 0x120)
            mstore(size, _owner)
            mstore(add(size, 0x20), _blast)
            mstore(add(size, 0x40), entropy)
            mstore(add(size, 0x60), token)
            mstore(add(size, 0x80), _rake)
            mstore(add(size, 0xa0), blockInterval)
            mstore(add(size, 0xc0), minBid)
            mstore(add(size, 0xe0), maxBid)

            pot := create2(0, add(bytecode, 32), add(size, 0x100), salt)

            // If the result of `create2` is the zero address, revert.
            if iszero(pot) {
                // Store the function selector of `DeploymentFailed()`.
                mstore(0x00, 0x30116425)
                revert(0x1c, 0x04)
            }
        }

        emit NewPot(pot, config);

        potByHash[salt] = pot;
        pots.push(pot);
    }

    /// @notice Unique identifier for pots to prevent duplication
    function potHash(uint256 blockInterval, uint256 minBid, uint256 maxBid, address token)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(blockInterval, minBid, maxBid, token));
    }

    /// @notice Total amount of pots
    function potsLength() external view returns (uint256) {
        return pots.length;
    }

    /// @notice Get all pots by token
    function potsByToken(address token) external view returns (address[] memory _pots) {
        uint256 length = 0;
        for (uint256 i = 0; i < pots.length; i++) {
            // Revert with (offset, size).
            if (Blastpot(payable(pots[i])).TOKEN() == token) {
                length++;
            }
        }
        _pots = new address[](length);
        uint256 index = 0;
        for (uint256 i = 0; i < pots.length; i++) {
            if (Blastpot(payable(pots[i])).TOKEN() == token) {
                _pots[index] = pots[i];
                index++;
            }
        }
    }
}

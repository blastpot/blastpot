// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "solady/tokens/ERC20.sol";

error ClaimNotReady();

contract MockYieldToken is ERC20 {
    uint256 private constant BIPS = 10000;
    uint256 public immutable BLOCK_COMPOUND_INTERVAL;
    uint256 public immutable REBASE_BIPS;

    mapping(address => uint256) lastBlockClaimed;

    constructor(uint256 _blockCompoundInterval, uint256 _rebaseBips) ERC20() {
        BLOCK_COMPOUND_INTERVAL = _blockCompoundInterval;
        REBASE_BIPS = _rebaseBips;
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function symbol() public pure override returns (string memory) {
        return "YLD";
    }

    function name() public pure override returns (string memory) {
        return "YieldToken";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function claimYieldTo(address to) external {
        _claimYield(msg.sender, to);
    }

    function claimYieldFor(address holder) external {
        _claimYield(holder, holder);
    }

    function _claimYield(address holder, address to) internal {
        uint256 lastBlock = lastBlockClaimed[holder];
        if (lastBlock == 0) {
            lastBlock = block.number;
        }
        if (block.number - lastBlock < BLOCK_COMPOUND_INTERVAL) {
            revert ClaimNotReady();
        }
        lastBlockClaimed[holder] = block.number;

        uint256 balance = balanceOf(holder);
        uint256 yield = balance * REBASE_BIPS / BIPS;
        _mint(to, yield);
    }
}

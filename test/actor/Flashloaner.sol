// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldPotFlashloanReceiver} from "interfaces/FlashloanReceiver.sol";
import {BlastpotYield} from "src/BlastpotYield.sol";
import {IERC20} from "interfaces/IERC20.sol";

contract Flashloaner is YieldPotFlashloanReceiver {
    address internal token;
    bool internal payFee = true;
    bool internal payAmount = true;

    constructor(address _token) {
        token = _token;
    }

    function flashloanNormal(address pot, uint256 amount) external {
        uint256 fee = _fee(pot, amount);
        IERC20(token).transferFrom(msg.sender, address(this), fee);

        BlastpotYield(payable(pot)).flashloan(amount, address(this));
    }

    function flashloanNoPayback(address pot, uint256 amount) external {
        payFee = false;
        payAmount = false;
        BlastpotYield(payable(pot)).flashloan(amount, address(this));
        payAmount = true;
        payFee = true;
    }

    function flashloanNoFee(address pot, uint256 amount) external {
        payFee = false;
        BlastpotYield(payable(pot)).flashloan(amount, address(this));
        payFee = true;
    }

    function flashloanMultiple(address pot, uint256 amount) external {
        uint256 fee = _fee(pot, amount);
        IERC20(token).transferFrom(msg.sender, address(this), fee);

        BlastpotYield(payable(pot)).flashloan(amount, address(this));
        payAmount = false;
        payFee = false;
        BlastpotYield(payable(pot)).flashloan(amount, address(this));
    }

    function _fee(address pot, uint256 amount) internal returns (uint256) {
        uint256 fee = BlastpotYield(payable(pot)).FLASHLOAN_FEE();
        return amount * fee / 10000;
    }

    function receiveLoan(uint256 amount) external override {
        // send back the money plus fee
        uint256 fee = payFee ? _fee(msg.sender, amount) : 0;
        uint256 total = payAmount ? amount + fee : fee;
        IERC20(token).transfer(payable(msg.sender), total);
    }
}

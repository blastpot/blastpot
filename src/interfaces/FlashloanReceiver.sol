// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface YieldPotFlashloanReceiver {
    function receiveLoan(uint256 amount) external;
}

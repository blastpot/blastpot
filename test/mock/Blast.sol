// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBlast, YieldMode, GasMode} from "../../src/interfaces/IBlast.sol";

contract MockBlast is IBlast {
    function configureContract(address contractAddress, YieldMode _yield, GasMode gasMode, address governor)
        external
        override
    {}
    function configure(YieldMode _yield, GasMode gasMode, address governor) external override {}

    function configureClaimableYield() external override {}
    function configureClaimableYieldOnBehalf(address contractAddress) external override {}
    function configureAutomaticYield() external override {}
    function configureAutomaticYieldOnBehalf(address contractAddress) external override {}
    function configureVoidYield() external override {}
    function configureVoidYieldOnBehalf(address contractAddress) external override {}

    function configureClaimableGas() external override {}
    function configureClaimableGasOnBehalf(address contractAddress) external override {}
    function configureVoidGas() external override {}
    function configureVoidGasOnBehalf(address contractAddress) external override {}

    function configureGovernor(address _governor) external override {}
    function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external override {}

    function claimYield(address contractAddress, address recipientOfYield, uint256 amount)
        external
        override
        returns (uint256)
    {}

    function claimAllYield(address contractAddress, address recipientOfYield) external override returns (uint256) {
        payable(recipientOfYield).transfer(0.01 ether);
        return 0.01 ether;
    }

    function claimAllGas(address contractAddress, address recipientOfGas) external override returns (uint256) {
        payable(recipientOfGas).transfer(0.01 ether);
        return 0.01 ether;
    }

    function claimGasAtMinClaimRate(address contractAddress, address recipientOfGas, uint256 minClaimRateBips)
        external
        override
        returns (uint256)
    {}
    function claimMaxGas(address contractAddress, address recipientOfGas) external override returns (uint256) {}
    function claimGas(address contractAddress, address recipientOfGas, uint256 gasToClaim, uint256 gasSecondsToConsume)
        external
        override
        returns (uint256)
    {}

    function readClaimableYield(address contractAddress) external view override returns (uint256) {}
    function readYieldConfiguration(address contractAddress) external view override returns (uint8) {}
    function readGasParams(address contractAddress)
        external
        view
        override
        returns (uint256 etherSeconds, uint256 etherBalance, uint256 lastUpdated, GasMode)
    {}

    receive() external payable {}
}

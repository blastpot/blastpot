// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {BlastpotRouter} from "src/BlastpotRouter.sol";
import {BlastpotFactory} from "src/BlastpotFactory.sol";

abstract contract DeployBase is Script {
    address internal immutable blast;
    uint256 internal immutable rake;

    constructor(address _blast, uint256 _rake) {
        blast = _blast;
        rake = _rake;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        BlastpotRouter router = new BlastpotRouter(blast);
        BlastpotFactory factory = new BlastpotFactory(rake, blast);

        vm.stopBroadcast();
    }
}

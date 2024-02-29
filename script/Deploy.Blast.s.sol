// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployBlast is DeployBase {
    address public immutable BLAST = 0x4300000000000000000000000000000000000002;
    uint256 public immutable RAKE = 500;

    constructor()
        // Blast Yield address
        DeployBase(
            BLAST,
            // Rake
            RAKE
        )
    {}
}

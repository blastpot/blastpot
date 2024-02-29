// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {Vm} from "forge-std/Vm.sol";
import {Blastpot} from "src/Blastpot.sol";
import {BlastpotFactory} from "src/BlastpotFactory.sol";
import {BlastpotRouter} from "src/BlastpotRouter.sol";
import {IERC20} from "interfaces/IERC20.sol";
import {console} from "utils/Console.sol";
import {Utilities} from "utils/Utilities.sol";
import {MockBlast} from "mock/Blast.sol";
import {MockEntropy} from "mock/Entropy.sol";

contract BlastpotIntegrationTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    BlastpotFactory internal pot;
    BlastpotRouter internal router;

    WETH internal weth;

    address internal entropy;
    address internal blast;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        blast = address(new MockBlast());
        pot = new BlastpotFactory(100, blast);
        entropy = users[4];
        weth = new WETH();

        vm.prank(users[0]);
        weth.deposit{value: 1000 ether}();
        vm.prank(users[1]);
        weth.deposit{value: 1000 ether}();
    }
}

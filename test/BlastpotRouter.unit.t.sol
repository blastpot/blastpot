// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Vm} from "forge-std/Vm.sol";
import {Blastpot} from "src/Blastpot.sol";
import {BlastpotRouter} from "src/BlastpotRouter.sol";
import {console} from "utils/Console.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {Utilities} from "utils/Utilities.sol";
import {MockBlast} from "mock/Blast.sol";
import {MockEntropy} from "mock/Entropy.sol";

contract BlastpotRouterUnitTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    MockBlast internal blast;
    BlastpotRouter internal router;

    WETH internal weth;

    address internal entropy;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        blast = new MockBlast();
        payable(address(blast)).transfer(1000 ether);
        entropy = address(new MockEntropy());
        weth = new WETH();

        router = new BlastpotRouter(address(blast));

        vm.prank(users[0]);
        weth.deposit{value: 1000 ether}();
    }

    function testSetUp() public {
        assertEq(router.owner(), address(this));
    }

    function testClaimGas() public {
        router.claimGas(address(this));

        vm.prank(users[0]);
        vm.expectRevert();
        router.claimGas(users[0]);
    }

    function testUpdateBlast() public {
        address newBlast = address(new MockBlast());
        router.updateBlast(newBlast);
        assertEq(router.blast(), newBlast);

        vm.prank(users[0]);
        vm.expectRevert();
        router.updateBlast(newBlast);
    }

    function testBidPots() public {
        address user = users[0];
        address[] memory pots = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        pots[0] =
            address(new Blastpot(address(this), address(blast), entropy, address(weth), 100, 150, 1, type(uint256).max));
        pots[1] =
            address(new Blastpot(address(this), address(blast), entropy, address(weth), 100, 150, 1, type(uint256).max));
        amounts[0] = 0.1 ether;
        amounts[1] = 0.1 ether;

        vm.startPrank(user);
        weth.approve(address(router), type(uint256).max);
        router.bid(pots, amounts);
        vm.stopPrank();
    }

    receive() external payable {}
}

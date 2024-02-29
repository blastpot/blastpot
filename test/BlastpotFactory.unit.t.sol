// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Vm} from "forge-std/Vm.sol";
import {Blastpot} from "src/Blastpot.sol";
import {BlastpotFactory} from "src/BlastpotFactory.sol";
import {console} from "utils/Console.sol";
import {Utilities} from "utils/Utilities.sol";
import {MockBlast} from "mock/Blast.sol";
import {MockEntropy} from "mock/Entropy.sol";

contract BlastpotFactoryUnitTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    BlastpotFactory internal pot;
    MockBlast internal blast;

    address internal entropy;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        blast = new MockBlast();
        payable(address(blast)).transfer(1000 ether);
        pot = new BlastpotFactory(100, address(blast));
        entropy = address(new MockEntropy());
    }

    function testSetUp() public {
        assertEq(pot.owner(), address(this));
    }

    function testAdjustRake() public {
        pot.adjustRake(100);
        assertEq(pot.rake(), 100);

        vm.prank(users[0]);
        vm.expectRevert();
        pot.adjustRake(100);
    }

    function testUpdateBlast() public {
        pot.updateBlast(address(blast));
        assertEq(pot.blast(), address(blast));

        vm.prank(users[0]);
        vm.expectRevert();
        pot.updateBlast(address(blast));
    }

    function testClaimGas() public {
        vm.expectRevert();
        vm.prank(users[1]);
        pot.claimGas(address(this));

        pot.claimGas(address(this));
    }

    function testNewPot(uint256 blockInterval, uint256 minBid, uint256 maxBid) public {
        vm.assume(blockInterval >= pot.MIN_BLOCK_INTERVAL() && blockInterval <= type(uint128).max);
        vm.assume(minBid != type(uint256).max && minBid != 0);
        vm.assume(maxBid >= minBid);
        address token = address(bytes20(keccak256("test")));
        address blastpot = pot.newPot(blockInterval, minBid, maxBid, token, entropy);

        assertNotEq(blastpot, address(0));

        assertEq(pot.pots(0), blastpot);
        assertEq(pot.potByHash(pot.potHash(blockInterval, minBid, maxBid, token)), blastpot);

        Blastpot chain = Blastpot(payable(blastpot));
        assertEq(chain.START_BLOCK(), block.number);
        assertEq(chain.BLOCK_INTERVAL(), blockInterval);
        assertEq(chain.MIN_BID(), minBid);
        assertEq(chain.MAX_BID(), maxBid);
        assertEq(chain.TOKEN(), token);
        assertEq(chain.entropy(), entropy);
        assertEq(chain.blastYieldManager(), address(blast));
        assertEq(chain.iteration(), 0);
    }

    function testPotsByToken() public {
        address token = address(bytes20(keccak256("test")));
        pot.newPot(150, 1, type(uint256).max, token, entropy);
        address[] memory pots = pot.potsByToken(token);
        assertGt(pots.length, 0);
        for (uint256 i = 0; i < pots.length; i++) {
            assertEq(Blastpot(payable(pots[i])).TOKEN(), token);
        }
    }

    receive() external payable {}
}

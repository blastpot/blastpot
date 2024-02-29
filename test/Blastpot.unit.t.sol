// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {Vm} from "forge-std/Vm.sol";
import "src/Blastpot.sol";
import {BlastpotFactory} from "src/BlastpotFactory.sol";
import {IERC20} from "interfaces/IERC20.sol";
import {console} from "utils/Console.sol";
import {Utilities} from "utils/Utilities.sol";
import {MockBlast} from "mock/Blast.sol";
import {MockEntropy} from "mock/Entropy.sol";

contract BlastpotUnitTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    BlastpotFactory internal factory;

    WETH internal weth;

    MockEntropy internal entropy;
    MockBlast internal blast;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        blast = new MockBlast();
        payable(address(blast)).transfer(1000 ether);
        factory = new BlastpotFactory(100, address(blast));
        entropy = new MockEntropy();
        weth = new WETH();

        vm.prank(users[0]);
        weth.deposit{value: 1000 ether}();
        vm.prank(users[1]);
        weth.deposit{value: 1000 ether}();
        vm.prank(users[2]);
        weth.deposit{value: 1000 ether}();
        vm.prank(users[3]);
        weth.deposit{value: 1000 ether}();
        vm.prank(users[4]);
        weth.deposit{value: 1000 ether}();
    }

    function testSetUp() public {
        assertEq(factory.owner(), address(this));
    }

    function testUpdateBlast() public {
        address newBlast = address(new MockBlast());
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));
        chain.updateBlastYieldManagement(newBlast);
        assertEq(chain.blastYieldManager(), newBlast);

        vm.prank(users[0]);
        vm.expectRevert();
        chain.updateBlastYieldManagement(newBlast);
    }

    function testUpdateEntropy() public {
        address newEntropy = address(new MockEntropy());
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));
        chain.updateEntropy(newEntropy);
        assertEq(chain.entropy(), newEntropy);

        vm.prank(users[0]);
        vm.expectRevert();
        chain.updateEntropy(newEntropy);
    }

    function testClaimYield() public {
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));
        chain.claimYield(address(this));

        vm.prank(users[0]);
        vm.expectRevert();
        chain.claimYield(users[0]);
    }

    function testClaimGas() public {
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));
        chain.claimGas(address(this));

        vm.prank(users[0]);
        vm.expectRevert();
        chain.claimGas(users[0]);
    }

    function testClaimRake() public {
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));
        chain.claimRake(address(this));

        vm.prank(users[0]);
        vm.expectRevert();
        chain.claimRake(users[0]);
    }

    function testBid(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000);
        address user = users[0];
        uint256 userBal = weth.balanceOf(user);
        address blastpot = newPot(1000, 1, type(uint256).max);
        Blastpot chain = Blastpot(payable(blastpot));

        assertEq(chain.iteration(), 0);

        uint256 bid = amount;
        vm.prank(user);
        weth.approve(blastpot, bid);
        vm.prank(user);
        chain.bid(user, amount);

        assertEq(weth.balanceOf(user), userBal - amount);
        assertEq(weth.balanceOf(blastpot), amount);
        assertEq(chain.iteration(), 0);
        assertEq(chain.bidRangeMax(0), bid);
    }

    function testDoubleBid(uint256 amount, uint256 amount2) public {
        vm.assume(amount > 0 && amount <= 1000);
        vm.assume(amount2 > 0 && amount2 <= 1000);
        address user = users[0];
        address user2 = users[1];
        address blastpot = newPot(1000, 1, type(uint256).max);
        Blastpot chain = Blastpot(payable(blastpot));
        uint256 iteration = chain.iteration();

        assertEq(iteration, 0);

        vm.prank(user);
        weth.approve(blastpot, amount);
        vm.prank(user);

        {
            uint256 index = chain.bid(user, amount);
            (address user1, uint256 min1, uint256 max1) = chain.bidRanges(iteration, index);

            assertEq(user1, user);
            assertEq(max1 - min1, amount);

            assertEq(chain.bidRangeMax(0), amount);
        }

        uint256 bid2 = amount2;
        vm.prank(user2);
        weth.approve(blastpot, bid2);
        vm.prank(user2);
        {
            uint256 index2 = chain.bid(user2, bid2);

            (address user2bid, uint256 min2, uint256 max2) = chain.bidRanges(iteration, index2);

            assertEq(user2bid, user2);
            assertEq(max2 - min2, bid2);

            assertEq(chain.bidRangeMax(0), amount + bid2);
        }
    }

    function testRequestEntropy() public {
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));
        vm.expectRevert(IterationIsNotOver.selector);
        chain.requestEntropy(address(0), 0);

        uint256 goalBlock = chain.iterationEndBlock(0);
        vm.roll(goalBlock);
        vm.expectRevert(InsufficientEntropyFee.selector);
        chain.requestEntropy(address(0), 0);

        (address provider, uint256 fee) = chain.entropyFee();
        chain.requestEntropy{value: fee}(provider, 0);

        vm.expectRevert(EntropyAlreadyRequested.selector);
        chain.requestEntropy{value: fee}(provider, 0);
    }

    function testWinner(uint256 random) public {
        Blastpot chain = Blastpot(payable(newPot(1000, 1, type(uint256).max)));

        bid(address(chain), users[0], (random % 30 ether) + 1);
        address winner = chain.winner(0, random);
        assertNotEq(winner, address(0));

        bid(address(chain), users[1], (random % 10 ether) + 1);
        winner = chain.winner(0, random);
        assertNotEq(winner, address(0));

        bid(address(chain), users[2], (random % 5 ether) + 1);
        winner = chain.winner(0, random);
        assertNotEq(winner, address(0));

        bid(address(chain), users[3], (random % 2.5 ether) + 1);
        winner = chain.winner(0, random);
        assertNotEq(winner, address(0));

        bid(address(chain), users[4], (random % 1 ether) + 1);
        winner = chain.winner(0, random);
        assertNotEq(winner, address(0));
    }

    function testRevealWinner(bytes32 random) public {
        uint256 total = 0.2 ether + 1 ether + 0.5 ether + 0.1 ether;

        address blastpot = newPot(1000, 1, type(uint256).max);
        Blastpot chain = Blastpot(payable(blastpot));

        bid(blastpot, users[0], 0.2 ether);
        bid(blastpot, users[1], 1 ether);
        bid(blastpot, users[2], 0.5 ether);
        bid(blastpot, users[3], 0.1 ether);

        vm.expectRevert(IterationIsNotOver.selector);
        chain.revealWinner(0, random);
        {
            uint256 goalBlock = chain.iterationEndBlock(0);
            vm.roll(goalBlock);
        }

        vm.expectRevert(EntropyNotRequested.selector);
        chain.revealWinner(0, random);

        requestEntropy(users[3], blastpot, 0);

        {
            uint256 bidLen = chain.iterationBids(0);
            assertEq(bidLen, 4);
        }
        assertEq(chain.bidRangeMax(0), total);
        {
            uint256 winningValue = uint256(random) % total;
            uint256 befBalance = address(this).balance;
            uint256 befBalance0 = users[3].balance;
            address winner = chain.revealWinner(0, random);

            assertGt(address(this).balance, befBalance);
            assertGt(users[3].balance, befBalance0);

            if (winningValue < 0.2 ether) {
                assertEq(winner, users[0]);
            } else if (winningValue < 0.2 ether + 1 ether) {
                assertEq(winner, users[1]);
            } else if (winningValue < 0.2 ether + 1 ether + 0.5 ether) {
                assertEq(winner, users[2]);
            } else {
                assertEq(winner, users[3]);
            }
        }
    }

    function testIterationStateGetters() public {
        address blastpot = newPot(1000, 1, type(uint256).max);
        Blastpot chain = Blastpot(payable(blastpot));

        bid(blastpot, users[0], 0.1 ether);
        bid(blastpot, users[1], 0.2 ether);
        bid(blastpot, users[2], 0.3 ether);

        uint256 bidLen = chain.iterationBids(0);
        assertEq(bidLen, 3);

        requestEntropy(users[4], blastpot, 0);
        bidLen = chain.iterationBids(0);
        assertEq(bidLen, 3);

        (Blastpot.BidRange[] memory ranges, Blastpot.EntropyRequest memory requested2) = chain.iterationState(0);
        assertEq(ranges[0].bidder, users[0]);
        assertEq(ranges[0].min, 0);
        assertEq(ranges[0].max, 0.1 ether);
        assertEq(ranges[1].bidder, users[1]);
        assertEq(ranges[1].min, 0.1 ether);
        assertEq(ranges[1].max, 0.3 ether);
        assertEq(ranges[2].bidder, users[2]);
        assertEq(ranges[2].min, 0.3 ether);
        assertEq(ranges[2].max, 0.6 ether);
        assertBoolEq(requested2.requested, true);
        assertEq(ranges.length, 3);
    }

    function newPot(uint256 blockInterval, uint256 minBid, uint256 maxBid) internal returns (address jackpot) {
        vm.assume(blockInterval >= factory.MIN_BLOCK_INTERVAL() && blockInterval <= type(uint128).max);
        vm.assume(minBid != type(uint256).max);
        vm.assume(maxBid >= minBid);
        address token = address(weth);
        jackpot = factory.newPot(blockInterval, minBid, maxBid, token, address(entropy));
    }

    function bid(address pot, address user, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(address(weth)).approve(pot, amount);
        Blastpot(payable(pot)).bid(user, amount);
        vm.stopPrank();
    }

    function requestEntropy(address requestor, address pot, uint256 iteration) internal {
        Blastpot pot = Blastpot(payable(pot));
        uint256 goalBlock = pot.iterationEndBlock(iteration);
        if (vm.getBlockNumber() < goalBlock) {
            vm.roll(goalBlock);
        }
        (address provider, uint256 fee) = pot.entropyFee();
        vm.startPrank(requestor);
        pot.requestEntropy{value: fee}(provider, iteration);
        vm.stopPrank();
    }

    receive() external payable {}
}

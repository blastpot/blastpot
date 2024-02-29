// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "utils/Console.sol";
import {Utilities} from "utils/Utilities.sol";
import {IERC20} from "interfaces/IERC20.sol";
import "src/BlastpotYield.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {MockEntropy} from "mock/Entropy.sol";
import {MockBlast} from "mock/Blast.sol";
import {IEntropy} from "entropy/IEntropy.sol";
import {Flashloaner} from "actor/Flashloaner.sol";

contract BlastpotYieldUnitTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    MockBlast internal blast;

    Utilities internal utils;
    address payable[] internal users;

    BlastpotYield internal yield;

    WETH internal weth;

    IEntropy internal entropy;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        entropy = new MockEntropy();
        blast = new MockBlast();
        payable(address(blast)).transfer(1000 ether);
        weth = new WETH();
        yield =
            new BlastpotYield(address(this), 100, address(weth), address(entropy), address(blast), 100, address(this));

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
        assertEq(yield.owner(), address(this));
        assertEq(yield.blastYieldManager(), address(blast));
        assertEq(yield.entropy(), address(entropy));
        assertEq(yield.TOKEN(), address(weth));
        assertEq(yield.START_BLOCK(), block.number);
        assertEq(yield.BLOCK_INTERVAL(), 100);
        assertEq(yield.iterationEndBlock(0), block.number + 100);

        assertEq(yield.iteration(), 0);
        assertEq(yield.liquidity(), 0);
        assertEq(yield.getAllBids().length, 0);

        vm.expectRevert(IterationIsNotOver.selector);
        yield.requestEntropy(0);
    }

    function testUpdateBlastYieldManagement() public {
        address newBlast = address(new MockBlast());

        yield.updateBlastYieldManagement(newBlast);
        assertEq(yield.blastYieldManager(), newBlast);

        vm.expectRevert();
        vm.prank(users[1]);
        yield.updateBlastYieldManagement(users[1]);
    }

    function testUpdateEntropy() public {
        address newEntropy = address(new MockEntropy());

        yield.updateEntropy(newEntropy);
        assertEq(yield.entropy(), newEntropy);

        vm.expectRevert();
        vm.prank(users[1]);
        yield.updateEntropy(users[1]);
    }

    function testBid() public {
        uint256 amount = 0.1 ether;
        uint256 random = uint256(keccak256("random"));
        address user = users[0];
        uint256 userBal = weth.balanceOf(user);

        bid(user, amount);

        assertEq(weth.balanceOf(user), userBal - amount);
        assertEq(weth.balanceOf(address(yield)), amount);
        assertEq(yield.liquidity(), amount);
        assertEq(yield.iteration(), 0);
        assertEq(yield.userByDeposit(amount), user);
        assertNotEq(yield.getBid(amount), bytes32(0));
        assertEq(yield.winner(amount, random), user);
    }

    function testWithdraw() public {
        uint256 amount = 0.1 ether;
        uint256 random = uint256(keccak256("random"));
        address user = users[0];
        uint256 userBal = weth.balanceOf(user);

        bid(user, amount);

        vm.prank(user);
        yield.withdraw(amount);

        assertEq(weth.balanceOf(user), userBal);
        assertEq(weth.balanceOf(address(yield)), 0);
        assertEq(yield.liquidity(), 0);
        assertEq(yield.iteration(), 0);
        assertEq(yield.userByDeposit(amount), address(0));
        assertEq(yield.getBid(amount), bytes32(0));
        vm.expectRevert();
        yield.winner(amount, random);
    }

    function testRequestEntropy() public {
        vm.roll(yield.START_BLOCK() + yield.BLOCK_INTERVAL());
        (, uint256 fee) = yield.entropyFee();

        yield.requestEntropy{value: fee}(0);

        vm.expectRevert(EntropyAlreadyRequested.selector);
        yield.requestEntropy{value: fee}(0);
    }

    function testWinner(uint256 random) public {
        bid(users[0], 0.1 ether);
        assertEq(yield.winner(0.1 ether, random), users[0]);

        bid(users[1], 0.2 ether);
        uint256 max = 0.3 ether;
        uint256 winner = random % max;
        if (winner < 0.1 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            assertEq(yield.closestBidTo(random), 0.1 ether);
            assertEq(yield.winner(0.1 ether, random), users[0]);
        } else {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            assertEq(yield.closestBidTo(random), 0.2 ether);
            assertEq(yield.winner(0.2 ether, random), users[1]);
        }

        bid(users[2], 0.3 ether);
        max += 0.3 ether;
        winner = random % max;
        if (winner < 0.1 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            assertEq(yield.closestBidTo(random), 0.1 ether);
            assertEq(yield.winner(0.1 ether, random), users[0]);
        } else if (winner < 0.3 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            assertEq(yield.closestBidTo(random), 0.2 ether);
            assertEq(yield.winner(0.2 ether, random), users[1]);
        } else {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            assertEq(yield.closestBidTo(random), 0.3 ether);
            assertEq(yield.winner(0.3 ether, random), users[2]);
        }

        bid(users[3], 0.4 ether);
        max += 0.4 ether;
        winner = random % max;
        if (winner < 0.1 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.closestBidTo(random), 0.1 ether);
            assertEq(yield.winner(0.1 ether, random), users[0]);
        } else if (winner < 0.3 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.closestBidTo(random), 0.2 ether);
            assertEq(yield.winner(0.2 ether, random), users[1]);
        } else if (winner < 0.6 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.closestBidTo(random), 0.3 ether);
            assertEq(yield.winner(0.3 ether, random), users[2]);
        } else {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            assertEq(yield.closestBidTo(random), 0.4 ether);
            assertEq(yield.winner(0.4 ether, random), users[3]);
        }

        console.log("four bids passed");

        bid(users[4], 0.11 ether);
        max += 0.11 ether;
        winner = random % max;
        if (winner < 0.1 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.11 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.winner(0.1 ether, random), users[0]);
        } else if (winner < 0.21 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.winner(0.11 ether, random), users[4]);
        } else if (winner < 0.41 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.11 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.winner(0.2 ether, random), users[1]);
        } else if (winner < 0.71 ether) {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.11 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.4 ether, random);
            assertEq(yield.winner(0.3 ether, random), users[2]);
        } else {
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.11 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.2 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.3 ether, random);
            vm.expectRevert(IncorrectClosestBid.selector);
            yield.winner(0.1 ether, random);
            assertEq(yield.winner(0.4 ether, random), users[3]);
        }
    }

    function testRevealWinner(uint256 random) public {
        bid(users[0], 0.1 ether);
        bid(users[1], 0.2 ether);

        requestEntropy(users[2], 0);

        uint256 _closestBid = yield.closestBidTo(random);
        address winner = yield.winner(_closestBid, random);
        uint256 requestBalance = users[2].balance;
        uint256 revealBalance = users[3].balance;
        uint256 winnerBalance = weth.balanceOf(winner);
        vm.prank(users[3]);
        yield.revealWinner(0, bytes32(random), _closestBid);
        assertGt(users[2].balance, requestBalance);
        assertGt(users[3].balance, revealBalance);
    }

    function testFlashloan(uint256 amount) public {
        vm.assume(amount < 1000 ether && amount > 0);
        bid(users[0], 1000 ether);
        assertEq(yield.liquidity(), 1000 ether);

        Flashloaner flashloaner = new Flashloaner(address(weth));

        vm.expectRevert();
        vm.prank(users[1]);
        flashloaner.flashloanNoPayback(address(yield), amount);

        if (amount > 99) {
            vm.expectRevert();
        }
        vm.prank(users[1]);
        flashloaner.flashloanNoFee(address(yield), amount);

        vm.prank(users[1]);
        IERC20(address(weth)).approve(address(flashloaner), type(uint256).max);
        vm.prank(users[1]);
        flashloaner.flashloanNormal(address(yield), amount);

        vm.expectRevert();
        vm.prank(users[1]);
        flashloaner.flashloanNoPayback(address(yield), amount);

        vm.expectRevert();
        vm.prank(users[1]);
        flashloaner.flashloanMultiple(address(yield), amount);
    }

    function bid(address user, uint256 amount) public {
        vm.startPrank(user);
        weth.approve(address(yield), amount);
        yield.bid(user, amount);
        vm.stopPrank();
    }

    function requestEntropy(address user, uint256 iteration) public {
        uint256 goalBlock = yield.iterationEndBlock(iteration);
        if (vm.getBlockNumber() < goalBlock) {
            vm.roll(goalBlock);
        }
        (, uint256 fee) = yield.entropyFee();
        vm.startPrank(user);
        yield.requestEntropy{value: fee}(iteration);
        vm.stopPrank();
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Settlement} from "../src/Settlement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SettlementTest is Test {
    Settlement public settlement;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public owner = address(this);
    address public guardian = makeAddr("guardian");
    address public verifier = makeAddr("verifier");
    address public permit2 = makeAddr("permit2");
    address public alice = makeAddr("alice");
    address public solver = makeAddr("solver");

    function setUp() public {
        settlement = new Settlement(permit2, verifier, guardian);
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
    }

    // ─── Deployment Tests ───────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(settlement.owner(), owner);
        assertEq(settlement.verifier(), verifier);
        assertEq(settlement.guardian(), guardian);
        assertEq(address(settlement.permit2()), permit2);
        assertFalse(settlement.paused());
    }

    // ─── Settle Tests ───────────────────────────────────────────────────

    function test_settle_simple_trade() public {
        // Mint tokens to participants
        tokenA.mint(alice, 1000e18);
        tokenB.mint(solver, 500e18);

        // Alice approves settlement to spend her tokenA
        vm.prank(alice);
        tokenA.approve(address(settlement), 1000e18);

        // Solver approves settlement to spend their tokenB
        vm.prank(solver);
        tokenB.approve(address(settlement), 500e18);

        // Build intent and solution
        Settlement.Intent memory intent = Settlement.Intent({
            sender: alice,
            sellToken: address(tokenA),
            sellAmount: 1000e18,
            buyToken: address(tokenB),
            minBuyAmount: 400e18,
            deadline: block.timestamp + 1 hours,
            nonce: 1
        });

        bytes32 intentHash = keccak256(
            abi.encode(
                intent.sender,
                intent.sellToken,
                intent.sellAmount,
                intent.buyToken,
                intent.minBuyAmount,
                intent.deadline,
                intent.nonce
            )
        );

        Settlement.Solution memory solution = Settlement.Solution({
            intentHash: intentHash,
            solver: solver,
            buyAmount: 500e18,
            route: ""
        });

        // Settle
        settlement.settle(intent, solution, "");

        // Verify balances
        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenA.balanceOf(solver), 1000e18);
        assertEq(tokenB.balanceOf(solver), 0);
        assertEq(tokenB.balanceOf(alice), 500e18);
    }

    function test_settle_reverts_expired_intent() public {
        Settlement.Intent memory intent = Settlement.Intent({
            sender: alice,
            sellToken: address(tokenA),
            sellAmount: 100e18,
            buyToken: address(tokenB),
            minBuyAmount: 50e18,
            deadline: block.timestamp - 1, // already expired
            nonce: 1
        });

        Settlement.Solution memory solution = Settlement.Solution({
            intentHash: bytes32(0),
            solver: solver,
            buyAmount: 50e18,
            route: ""
        });

        vm.expectRevert(Settlement.IntentExpired.selector);
        settlement.settle(intent, solution, "");
    }

    function test_settle_reverts_nonce_reuse() public {
        // Setup balances and approvals
        tokenA.mint(alice, 2000e18);
        tokenB.mint(solver, 1000e18);
        vm.prank(alice);
        tokenA.approve(address(settlement), type(uint256).max);
        vm.prank(solver);
        tokenB.approve(address(settlement), type(uint256).max);

        Settlement.Intent memory intent = Settlement.Intent({
            sender: alice,
            sellToken: address(tokenA),
            sellAmount: 100e18,
            buyToken: address(tokenB),
            minBuyAmount: 50e18,
            deadline: block.timestamp + 1 hours,
            nonce: 42
        });

        bytes32 intentHash = keccak256(
            abi.encode(
                intent.sender, intent.sellToken, intent.sellAmount,
                intent.buyToken, intent.minBuyAmount, intent.deadline, intent.nonce
            )
        );

        Settlement.Solution memory solution = Settlement.Solution({
            intentHash: intentHash,
            solver: solver,
            buyAmount: 50e18,
            route: ""
        });

        // First settle succeeds
        settlement.settle(intent, solution, "");

        // Second settle with same nonce reverts
        vm.expectRevert(Settlement.NonceAlreadyUsed.selector);
        settlement.settle(intent, solution, "");
    }

    function test_settle_reverts_insufficient_buy_amount() public {
        Settlement.Intent memory intent = Settlement.Intent({
            sender: alice,
            sellToken: address(tokenA),
            sellAmount: 100e18,
            buyToken: address(tokenB),
            minBuyAmount: 100e18,
            deadline: block.timestamp + 1 hours,
            nonce: 1
        });

        Settlement.Solution memory solution = Settlement.Solution({
            intentHash: bytes32(0),
            solver: solver,
            buyAmount: 50e18, // less than minBuyAmount
            route: ""
        });

        vm.expectRevert(Settlement.InsufficientBuyAmount.selector);
        settlement.settle(intent, solution, "");
    }

    // ─── Batch Settle Tests ─────────────────────────────────────────────

    function test_settleBatch_two_intents() public {
        address alice2 = makeAddr("alice2");

        tokenA.mint(alice, 100e18);
        tokenA.mint(alice2, 200e18);
        tokenB.mint(solver, 300e18);

        vm.prank(alice);
        tokenA.approve(address(settlement), type(uint256).max);
        vm.prank(alice2);
        tokenA.approve(address(settlement), type(uint256).max);
        vm.prank(solver);
        tokenB.approve(address(settlement), type(uint256).max);

        Settlement.Intent[] memory intents = new Settlement.Intent[](2);
        intents[0] = Settlement.Intent({
            sender: alice,
            sellToken: address(tokenA),
            sellAmount: 100e18,
            buyToken: address(tokenB),
            minBuyAmount: 80e18,
            deadline: block.timestamp + 1 hours,
            nonce: 1
        });
        intents[1] = Settlement.Intent({
            sender: alice2,
            sellToken: address(tokenA),
            sellAmount: 200e18,
            buyToken: address(tokenB),
            minBuyAmount: 150e18,
            deadline: block.timestamp + 1 hours,
            nonce: 1
        });

        Settlement.Solution[] memory solutions = new Settlement.Solution[](2);
        solutions[0] = Settlement.Solution({
            intentHash: bytes32(0),
            solver: solver,
            buyAmount: 90e18,
            route: ""
        });
        solutions[1] = Settlement.Solution({
            intentHash: bytes32(0),
            solver: solver,
            buyAmount: 180e18,
            route: ""
        });

        settlement.settleBatch(intents, solutions, "");

        assertEq(tokenA.balanceOf(solver), 300e18);
        assertEq(tokenB.balanceOf(alice), 90e18);
        assertEq(tokenB.balanceOf(alice2), 180e18);
    }

    function test_settleBatch_reverts_length_mismatch() public {
        Settlement.Intent[] memory intents = new Settlement.Intent[](2);
        Settlement.Solution[] memory solutions = new Settlement.Solution[](1);

        vm.expectRevert(Settlement.ArrayLengthMismatch.selector);
        settlement.settleBatch(intents, solutions, "");
    }

    // ─── Pause Tests ────────────────────────────────────────────────────

    function test_pause_by_guardian() public {
        vm.prank(guardian);
        settlement.pause();
        assertTrue(settlement.paused());
    }

    function test_unpause_by_guardian() public {
        vm.prank(guardian);
        settlement.pause();
        vm.prank(guardian);
        settlement.unpause();
        assertFalse(settlement.paused());
    }

    function test_pause_reverts_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(Settlement.Unauthorized.selector);
        settlement.pause();
    }

    function test_settle_reverts_when_paused() public {
        vm.prank(guardian);
        settlement.pause();

        Settlement.Intent memory intent = Settlement.Intent({
            sender: alice,
            sellToken: address(tokenA),
            sellAmount: 100e18,
            buyToken: address(tokenB),
            minBuyAmount: 50e18,
            deadline: block.timestamp + 1 hours,
            nonce: 1
        });

        Settlement.Solution memory solution = Settlement.Solution({
            intentHash: bytes32(0),
            solver: solver,
            buyAmount: 50e18,
            route: ""
        });

        vm.expectRevert(Settlement.ContractPaused.selector);
        settlement.settle(intent, solution, "");
    }

    // ─── Admin Tests ────────────────────────────────────────────────────

    function test_setVerifier() public {
        address newVerifier = makeAddr("newVerifier");
        settlement.setVerifier(newVerifier);
        assertEq(settlement.verifier(), newVerifier);
    }

    function test_setGuardian() public {
        address newGuardian = makeAddr("newGuardian");
        settlement.setGuardian(newGuardian);
        assertEq(settlement.guardian(), newGuardian);
    }

    function test_setVerifier_reverts_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(Settlement.Unauthorized.selector);
        settlement.setVerifier(alice);
    }
}

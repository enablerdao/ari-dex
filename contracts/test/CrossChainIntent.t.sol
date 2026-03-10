// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CrossChainIntent} from "../src/CrossChainIntent.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract CrossChainIntentTest is Test {
    CrossChainIntent public cci;
    MockERC20 public originToken;
    MockERC20 public destToken;

    address public alice = makeAddr("alice");
    address public solver = makeAddr("solver");

    function setUp() public {
        cci = new CrossChainIntent();
        originToken = new MockERC20("Origin Token", "OTK");
        destToken = new MockERC20("Dest Token", "DTK");

        // Fund alice with origin tokens and approve
        originToken.mint(alice, 1000e18);
        vm.prank(alice);
        originToken.approve(address(cci), type(uint256).max);

        // Fund solver with destination tokens and approve
        destToken.mint(solver, 1000e18);
        vm.prank(solver);
        destToken.approve(address(cci), type(uint256).max);
    }

    // ─── Deployment Tests ───────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(cci.owner(), address(this));
        assertEq(cci.nextOrderId(), 1);
    }

    // ─── Open Tests ─────────────────────────────────────────────────────

    function test_open() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);

        vm.prank(alice);
        uint256 orderId = cci.open(order);
        assertEq(orderId, 1);
        assertEq(cci.nextOrderId(), 2);

        // Tokens escrowed
        assertEq(originToken.balanceOf(address(cci)), 100e18);
        assertEq(originToken.balanceOf(alice), 900e18);

        CrossChainIntent.CrossChainOrder memory stored = cci.getOrder(orderId);
        assertEq(stored.user, alice);
        assertEq(stored.originAmount, 100e18);
        assertEq(stored.minDestinationAmount, 90e18);
    }

    function test_open_multiple_orders() public {
        CrossChainIntent.CrossChainOrder memory order1 = _makeOrder(alice, 1);
        CrossChainIntent.CrossChainOrder memory order2 = _makeOrder(alice, 2);

        vm.prank(alice);
        uint256 id1 = cci.open(order1);
        vm.prank(alice);
        uint256 id2 = cci.open(order2);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(originToken.balanceOf(address(cci)), 200e18);
    }

    function test_open_reverts_zero_amount() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        order.originAmount = 0;

        vm.expectRevert(CrossChainIntent.ZeroAmount.selector);
        cci.open(order);
    }

    function test_open_reverts_expired() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        order.deadline = block.timestamp - 1;

        vm.expectRevert(CrossChainIntent.OrderExpired.selector);
        cci.open(order);
    }

    function test_open_reverts_nonce_reuse() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        cci.open(order);

        vm.expectRevert(CrossChainIntent.NonceAlreadyUsed.selector);
        cci.open(order);
    }

    // ─── Fill Tests ─────────────────────────────────────────────────────

    function test_fill() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        // Solver fills - provides dest tokens to user, gets origin tokens
        vm.prank(solver);
        cci.fill(orderId, fillData);

        CrossChainIntent.Resolution memory res = cci.getResolution(orderId);
        assertTrue(res.filled);
        assertEq(res.solver, solver);
        assertEq(res.destinationAmount, 95e18);

        // Verify token flows
        assertEq(destToken.balanceOf(alice), 95e18); // alice got dest tokens
        assertEq(originToken.balanceOf(solver), 100e18); // solver got origin tokens
        assertEq(originToken.balanceOf(address(cci)), 0); // escrow empty
    }

    function test_fill_reverts_order_not_found() public {
        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        vm.expectRevert(CrossChainIntent.OrderNotFound.selector);
        cci.fill(999, fillData);
    }

    function test_fill_reverts_already_filled() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        vm.prank(solver);
        cci.fill(orderId, fillData);

        vm.prank(solver);
        vm.expectRevert(CrossChainIntent.OrderAlreadyFilled.selector);
        cci.fill(orderId, fillData);
    }

    function test_fill_reverts_insufficient_amount() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 80e18, // below minDestinationAmount of 90e18
            proof: ""
        });

        vm.prank(solver);
        vm.expectRevert(CrossChainIntent.InsufficientFillAmount.selector);
        cci.fill(orderId, fillData);
    }

    function test_fill_reverts_expired_order() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        vm.warp(block.timestamp + 2 hours);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        vm.prank(solver);
        vm.expectRevert(CrossChainIntent.OrderExpired.selector);
        cci.fill(orderId, fillData);
    }

    // ─── Cancel Tests ───────────────────────────────────────────────────

    function test_cancel_after_deadline() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        uint256 balBefore = originToken.balanceOf(alice);

        vm.prank(alice);
        cci.cancel(orderId);

        // Tokens returned
        assertEq(originToken.balanceOf(alice), balBefore + 100e18);
        assertEq(originToken.balanceOf(address(cci)), 0);
        assertTrue(cci.cancelled(orderId));
    }

    function test_cancel_reverts_before_deadline() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        vm.prank(alice);
        vm.expectRevert(CrossChainIntent.OrderNotExpired.selector);
        cci.cancel(orderId);
    }

    function test_cancel_reverts_unauthorized() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(solver);
        vm.expectRevert(CrossChainIntent.Unauthorized.selector);
        cci.cancel(orderId);
    }

    function test_cancel_reverts_already_filled() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        vm.prank(solver);
        cci.fill(orderId, fillData);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(alice);
        vm.expectRevert(CrossChainIntent.OrderAlreadyFilled.selector);
        cci.cancel(orderId);
    }

    // ─── Resolve Tests ──────────────────────────────────────────────────

    function test_resolve() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        vm.prank(solver);
        cci.fill(orderId, fillData);

        CrossChainIntent.Resolution memory res = cci.resolve(orderId);
        assertTrue(res.filled);
        assertEq(res.solver, solver);
        assertEq(res.destinationAmount, 95e18);
    }

    function test_resolve_reverts_not_filled() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        vm.prank(alice);
        uint256 orderId = cci.open(order);

        vm.expectRevert(CrossChainIntent.OrderNotFilled.selector);
        cci.resolve(orderId);
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _makeOrder(address user, uint256 nonce)
        internal
        view
        returns (CrossChainIntent.CrossChainOrder memory)
    {
        return CrossChainIntent.CrossChainOrder({
            user: user,
            originChainId: 1,
            destinationChainId: 42161,
            originToken: address(originToken),
            originAmount: 100e18,
            destinationToken: address(destToken),
            minDestinationAmount: 90e18,
            deadline: block.timestamp + 1 hours,
            nonce: nonce,
            orderData: ""
        });
    }
}

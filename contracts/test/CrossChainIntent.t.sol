// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CrossChainIntent} from "../src/CrossChainIntent.sol";

contract CrossChainIntentTest is Test {
    CrossChainIntent public cci;

    address public alice = makeAddr("alice");
    address public solver = makeAddr("solver");
    address public tokenA = makeAddr("tokenA");
    address public tokenB = makeAddr("tokenB");

    function setUp() public {
        cci = new CrossChainIntent();
    }

    // ─── Deployment Tests ───────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(cci.owner(), address(this));
        assertEq(cci.nextOrderId(), 1);
    }

    // ─── Open Tests ─────────────────────────────────────────────────────

    function test_open() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);

        uint256 orderId = cci.open(order);
        assertEq(orderId, 1);
        assertEq(cci.nextOrderId(), 2);

        CrossChainIntent.CrossChainOrder memory stored = cci.getOrder(orderId);
        assertEq(stored.user, alice);
        assertEq(stored.originAmount, 100e18);
        assertEq(stored.minDestinationAmount, 90e18);
    }

    function test_open_multiple_orders() public {
        CrossChainIntent.CrossChainOrder memory order1 = _makeOrder(alice, 1);
        CrossChainIntent.CrossChainOrder memory order2 = _makeOrder(alice, 2);

        uint256 id1 = cci.open(order1);
        uint256 id2 = cci.open(order2);

        assertEq(id1, 1);
        assertEq(id2, 2);
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
        cci.open(order);

        vm.expectRevert(CrossChainIntent.NonceAlreadyUsed.selector);
        cci.open(order);
    }

    // ─── Fill Tests ─────────────────────────────────────────────────────

    function test_fill() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        cci.fill(orderId, fillData);

        CrossChainIntent.Resolution memory res = cci.getResolution(orderId);
        assertTrue(res.filled);
        assertEq(res.solver, solver);
        assertEq(res.destinationAmount, 95e18);
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
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        cci.fill(orderId, fillData);

        vm.expectRevert(CrossChainIntent.OrderAlreadyFilled.selector);
        cci.fill(orderId, fillData);
    }

    function test_fill_reverts_insufficient_amount() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 80e18, // below minDestinationAmount of 90e18
            proof: ""
        });

        vm.expectRevert(CrossChainIntent.InsufficientFillAmount.selector);
        cci.fill(orderId, fillData);
    }

    function test_fill_reverts_expired_order() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        uint256 orderId = cci.open(order);

        vm.warp(block.timestamp + 2 hours);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        vm.expectRevert(CrossChainIntent.OrderExpired.selector);
        cci.fill(orderId, fillData);
    }

    // ─── Resolve Tests ──────────────────────────────────────────────────

    function test_resolve() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
        uint256 orderId = cci.open(order);

        CrossChainIntent.FillData memory fillData = CrossChainIntent.FillData({
            solver: solver,
            destinationAmount: 95e18,
            proof: ""
        });

        cci.fill(orderId, fillData);

        CrossChainIntent.Resolution memory res = cci.resolve(orderId);
        assertTrue(res.filled);
        assertEq(res.solver, solver);
        assertEq(res.destinationAmount, 95e18);
    }

    function test_resolve_reverts_not_filled() public {
        CrossChainIntent.CrossChainOrder memory order = _makeOrder(alice, 1);
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
            originToken: tokenA,
            originAmount: 100e18,
            destinationToken: tokenB,
            minDestinationAmount: 90e18,
            deadline: block.timestamp + 1 hours,
            nonce: nonce,
            orderData: ""
        });
    }
}

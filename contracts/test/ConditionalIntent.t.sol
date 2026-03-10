// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ConditionalIntent} from "../src/ConditionalIntent.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract ConditionalIntentTest is Test {
    ConditionalIntent public ci;
    MockERC20 public tokenA; // sell token
    MockERC20 public tokenB; // buy token

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public keeper = makeAddr("keeper");

    uint256 constant SELL_AMOUNT = 1000e18;
    uint256 constant MIN_BUY = 500e18;
    uint256 constant TRIGGER_PRICE = 3000_000000; // $3000 (6 decimals)

    function setUp() public {
        ci = new ConditionalIntent();
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        // Fund alice
        tokenA.mint(alice, 10_000e18);
        vm.prank(alice);
        tokenA.approve(address(ci), type(uint256).max);
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _createLimitOrder() internal returns (uint256) {
        vm.prank(alice);
        return ci.createLimitOrder(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );
    }

    // ─── Limit Order Tests ──────────────────────────────────────────────

    function test_createLimitOrder_and_execute() public {
        uint256 orderId = _createLimitOrder();

        // Tokens escrowed
        assertEq(tokenA.balanceOf(address(ci)), SELL_AMOUNT);
        assertEq(tokenA.balanceOf(alice), 10_000e18 - SELL_AMOUNT);

        // Order stored correctly
        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(order.owner, alice);
        assertEq(uint8(order.orderType), uint8(ConditionalIntent.OrderType.Limit));
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Active));
        assertEq(order.sellAmount, SELL_AMOUNT);
        assertEq(order.triggerPrice, TRIGGER_PRICE);

        // Execute when price <= trigger
        uint256 currentPrice = 2900_000000; // $2900 <= $3000 trigger
        vm.prank(keeper);
        ci.executeOrder(orderId, currentPrice);

        // Keeper received sell tokens
        assertEq(tokenA.balanceOf(keeper), SELL_AMOUNT);

        // Order marked executed
        order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Executed));
    }

    function test_limitOrder_revert_when_price_not_met() public {
        uint256 orderId = _createLimitOrder();

        // Price above trigger — should revert
        uint256 highPrice = 3100_000000; // $3100 > $3000 trigger
        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.TriggerNotMet.selector);
        ci.executeOrder(orderId, highPrice);
    }

    // ─── Stop-Loss Tests ────────────────────────────────────────────────

    function test_createStopLoss_and_execute() public {
        vm.prank(alice);
        uint256 orderId = ci.createStopLoss(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        // Execute when price <= trigger (price dropped)
        uint256 currentPrice = 2500_000000;
        vm.prank(keeper);
        ci.executeOrder(orderId, currentPrice);

        assertEq(tokenA.balanceOf(keeper), SELL_AMOUNT);
        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Executed));
    }

    function test_stopLoss_revert_when_price_above_trigger() public {
        vm.prank(alice);
        uint256 orderId = ci.createStopLoss(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.TriggerNotMet.selector);
        ci.executeOrder(orderId, 3500_000000);
    }

    // ─── Take-Profit Tests ──────────────────────────────────────────────

    function test_createTakeProfit_and_execute() public {
        vm.prank(alice);
        uint256 orderId = ci.createTakeProfit(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        // Execute when price >= trigger (price rose)
        uint256 currentPrice = 3500_000000;
        vm.prank(keeper);
        ci.executeOrder(orderId, currentPrice);

        assertEq(tokenA.balanceOf(keeper), SELL_AMOUNT);
        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Executed));
    }

    function test_takeProfit_revert_when_price_below_trigger() public {
        vm.prank(alice);
        uint256 orderId = ci.createTakeProfit(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.TriggerNotMet.selector);
        ci.executeOrder(orderId, 2900_000000);
    }

    // ─── DCA Tests ──────────────────────────────────────────────────────

    function test_createDCA_and_multiple_executions() public {
        uint256 totalAmount = 1000e18;
        uint256 perExecution = 250e18;
        uint256 interval = 1 hours;

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            totalAmount, perExecution, interval,
            block.timestamp + 30 days
        );

        // All tokens escrowed
        assertEq(tokenA.balanceOf(address(ci)), totalAmount);

        // Execute 4 tranches
        for (uint256 i; i < 4; ++i) {
            if (i > 0) {
                vm.warp(block.timestamp + interval);
            }
            vm.prank(keeper);
            ci.executeDCA(orderId, 3000_000000);
        }

        // Keeper received all tokens
        assertEq(tokenA.balanceOf(keeper), totalAmount);
        assertEq(tokenA.balanceOf(address(ci)), 0);

        // Order fully executed
        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Executed));
    }

    function test_DCA_interval_enforcement() public {
        uint256 interval = 1 hours;

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            1000e18, 250e18, interval,
            block.timestamp + 30 days
        );

        // First execution succeeds
        vm.prank(keeper);
        ci.executeDCA(orderId, 3000_000000);

        // Second execution too early — should revert
        vm.warp(block.timestamp + 30 minutes); // only 30 min, need 1 hour
        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.DCAIntervalNotElapsed.selector);
        ci.executeDCA(orderId, 3000_000000);

        // After enough time passes, it should succeed
        vm.warp(block.timestamp + 31 minutes); // total 61 min from first
        vm.prank(keeper);
        ci.executeDCA(orderId, 3000_000000);
    }

    function test_DCA_fully_executed_revert() public {
        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            500e18, 500e18, 1 hours,
            block.timestamp + 30 days
        );

        // Execute the single tranche
        vm.prank(keeper);
        ci.executeDCA(orderId, 3000_000000);

        // Now fully executed — try again should revert with OrderNotActive
        vm.warp(block.timestamp + 2 hours);
        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.OrderNotActive.selector);
        ci.executeDCA(orderId, 3000_000000);
    }

    // ─── Cancel Tests ───────────────────────────────────────────────────

    function test_cancelOrder_and_refund() public {
        uint256 orderId = _createLimitOrder();

        uint256 balanceBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        ci.cancelOrder(orderId);

        // Tokens refunded
        assertEq(tokenA.balanceOf(alice), balanceBefore + SELL_AMOUNT);
        assertEq(tokenA.balanceOf(address(ci)), 0);

        // Order marked cancelled
        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Cancelled));
    }

    function test_cancelDCA_partial_refund() public {
        uint256 totalAmount = 1000e18;
        uint256 perExecution = 250e18;

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            totalAmount, perExecution, 1 hours,
            block.timestamp + 30 days
        );

        // Execute one tranche
        vm.prank(keeper);
        ci.executeDCA(orderId, 3000_000000);

        // Cancel — should refund remaining 750e18
        uint256 balanceBefore = tokenA.balanceOf(alice);
        vm.prank(alice);
        ci.cancelOrder(orderId);

        assertEq(tokenA.balanceOf(alice), balanceBefore + 750e18);
    }

    function test_unauthorized_cancel_revert() public {
        uint256 orderId = _createLimitOrder();

        vm.prank(bob);
        vm.expectRevert(ConditionalIntent.Unauthorized.selector);
        ci.cancelOrder(orderId);
    }

    // ─── Expiry Tests ───────────────────────────────────────────────────

    function test_expired_order_revert() public {
        uint256 orderId = _createLimitOrder();

        // Warp past deadline
        vm.warp(block.timestamp + 2 days);

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.OrderExpired.selector);
        ci.executeOrder(orderId, 2900_000000);
    }

    // ─── getActiveOrders Tests ──────────────────────────────────────────

    function test_getActiveOrders() public {
        // Create 3 orders
        uint256 id0 = _createLimitOrder();

        vm.prank(alice);
        uint256 id1 = ci.createStopLoss(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        vm.prank(alice);
        uint256 id2 = ci.createTakeProfit(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        // All 3 active
        uint256[] memory active = ci.getActiveOrders(alice);
        assertEq(active.length, 3);
        assertEq(active[0], id0);
        assertEq(active[1], id1);
        assertEq(active[2], id2);

        // Cancel one
        vm.prank(alice);
        ci.cancelOrder(id1);

        // Now 2 active
        active = ci.getActiveOrders(alice);
        assertEq(active.length, 2);
        assertEq(active[0], id0);
        assertEq(active[1], id2);

        // Execute one
        vm.prank(keeper);
        ci.executeOrder(id0, 2900_000000);

        // Now 1 active
        active = ci.getActiveOrders(alice);
        assertEq(active.length, 1);
        assertEq(active[0], id2);

        // Bob has no orders
        active = ci.getActiveOrders(bob);
        assertEq(active.length, 0);
    }
}

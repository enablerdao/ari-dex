// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ConditionalIntent} from "../src/ConditionalIntent.sol";
import {SimplePriceOracle} from "../src/SimplePriceOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract ConditionalIntentTest is Test {
    ConditionalIntent public ci;
    SimplePriceOracle public oracle;
    MockERC20 public tokenA; // sell token
    MockERC20 public tokenB; // buy token

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public keeper = makeAddr("keeper");

    uint256 constant SELL_AMOUNT = 1000e18;
    uint256 constant MIN_BUY = 500e18;
    uint256 constant TRIGGER_PRICE = 3000_000000; // $3000 (6 decimals)

    function setUp() public {
        oracle = new SimplePriceOracle();
        ci = new ConditionalIntent(address(oracle));
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

    function _setOraclePrice(uint256 price) internal {
        oracle.setPrice(address(tokenA), price);
    }

    // ─── Limit Order Tests ──────────────────────────────────────────────

    function test_createLimitOrder_and_execute() public {
        uint256 orderId = _createLimitOrder();

        assertEq(tokenA.balanceOf(address(ci)), SELL_AMOUNT);
        assertEq(tokenA.balanceOf(alice), 10_000e18 - SELL_AMOUNT);

        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(order.owner, alice);
        assertEq(uint8(order.orderType), uint8(ConditionalIntent.OrderType.Limit));
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Active));
        assertEq(order.sellAmount, SELL_AMOUNT);
        assertEq(order.triggerPrice, TRIGGER_PRICE);

        // Set oracle price <= trigger
        _setOraclePrice(2900_000000); // $2900 <= $3000 trigger

        vm.prank(keeper);
        ci.executeOrder(orderId);

        assertEq(tokenA.balanceOf(keeper), SELL_AMOUNT);

        order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Executed));
    }

    function test_limitOrder_revert_when_price_not_met() public {
        uint256 orderId = _createLimitOrder();

        // Price above trigger
        _setOraclePrice(3100_000000); // $3100 > $3000 trigger

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.TriggerNotMet.selector);
        ci.executeOrder(orderId);
    }

    // ─── Stop-Loss Tests ────────────────────────────────────────────────

    function test_createStopLoss_and_execute() public {
        vm.prank(alice);
        uint256 orderId = ci.createStopLoss(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        _setOraclePrice(2500_000000);

        vm.prank(keeper);
        ci.executeOrder(orderId);

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

        _setOraclePrice(3500_000000);

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.TriggerNotMet.selector);
        ci.executeOrder(orderId);
    }

    // ─── Take-Profit Tests ──────────────────────────────────────────────

    function test_createTakeProfit_and_execute() public {
        vm.prank(alice);
        uint256 orderId = ci.createTakeProfit(
            address(tokenA), address(tokenB),
            SELL_AMOUNT, MIN_BUY, TRIGGER_PRICE,
            block.timestamp + 1 days
        );

        _setOraclePrice(3500_000000);

        vm.prank(keeper);
        ci.executeOrder(orderId);

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

        _setOraclePrice(2900_000000);

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.TriggerNotMet.selector);
        ci.executeOrder(orderId);
    }

    // ─── DCA Tests ──────────────────────────────────────────────────────

    function test_createDCA_and_multiple_executions() public {
        uint256 totalAmount = 1000e18;
        uint256 perExecution = 250e18;
        uint256 interval = 1 hours;

        // Set oracle price for DCA (informational)
        _setOraclePrice(3000_000000);

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            totalAmount, perExecution, interval,
            block.timestamp + 30 days
        );

        assertEq(tokenA.balanceOf(address(ci)), totalAmount);

        for (uint256 i; i < 4; ++i) {
            if (i > 0) {
                vm.warp(block.timestamp + interval);
            }
            vm.prank(keeper);
            ci.executeDCA(orderId);
        }

        assertEq(tokenA.balanceOf(keeper), totalAmount);
        assertEq(tokenA.balanceOf(address(ci)), 0);

        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Executed));
    }

    function test_DCA_interval_enforcement() public {
        uint256 interval = 1 hours;

        _setOraclePrice(3000_000000);

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            1000e18, 250e18, interval,
            block.timestamp + 30 days
        );

        vm.prank(keeper);
        ci.executeDCA(orderId);

        vm.warp(block.timestamp + 30 minutes);
        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.DCAIntervalNotElapsed.selector);
        ci.executeDCA(orderId);

        vm.warp(block.timestamp + 31 minutes);
        vm.prank(keeper);
        ci.executeDCA(orderId);
    }

    function test_DCA_fully_executed_revert() public {
        _setOraclePrice(3000_000000);

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            500e18, 500e18, 1 hours,
            block.timestamp + 30 days
        );

        vm.prank(keeper);
        ci.executeDCA(orderId);

        vm.warp(block.timestamp + 2 hours);
        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.OrderNotActive.selector);
        ci.executeDCA(orderId);
    }

    // ─── Cancel Tests ───────────────────────────────────────────────────

    function test_cancelOrder_and_refund() public {
        uint256 orderId = _createLimitOrder();

        uint256 balanceBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        ci.cancelOrder(orderId);

        assertEq(tokenA.balanceOf(alice), balanceBefore + SELL_AMOUNT);
        assertEq(tokenA.balanceOf(address(ci)), 0);

        ConditionalIntent.ConditionalOrder memory order = ci.getOrder(orderId);
        assertEq(uint8(order.status), uint8(ConditionalIntent.OrderStatus.Cancelled));
    }

    function test_cancelDCA_partial_refund() public {
        uint256 totalAmount = 1000e18;
        uint256 perExecution = 250e18;

        _setOraclePrice(3000_000000);

        vm.prank(alice);
        uint256 orderId = ci.createDCA(
            address(tokenA), address(tokenB),
            totalAmount, perExecution, 1 hours,
            block.timestamp + 30 days
        );

        vm.prank(keeper);
        ci.executeDCA(orderId);

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

        _setOraclePrice(2900_000000);

        vm.warp(block.timestamp + 2 days);

        vm.prank(keeper);
        vm.expectRevert(ConditionalIntent.OrderExpired.selector);
        ci.executeOrder(orderId);
    }

    // ─── getActiveOrders Tests ──────────────────────────────────────────

    function test_getActiveOrders() public {
        _setOraclePrice(2900_000000);

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

        uint256[] memory active = ci.getActiveOrders(alice);
        assertEq(active.length, 3);
        assertEq(active[0], id0);
        assertEq(active[1], id1);
        assertEq(active[2], id2);

        vm.prank(alice);
        ci.cancelOrder(id1);

        active = ci.getActiveOrders(alice);
        assertEq(active.length, 2);
        assertEq(active[0], id0);
        assertEq(active[1], id2);

        vm.prank(keeper);
        ci.executeOrder(id0);

        active = ci.getActiveOrders(alice);
        assertEq(active.length, 1);
        assertEq(active[0], id2);

        active = ci.getActiveOrders(bob);
        assertEq(active.length, 0);
    }
}

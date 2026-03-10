// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PerpetualMarket} from "../src/PerpetualMarket.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PerpetualMarketTest is Test {
    PerpetualMarket market;
    MockERC20 usdc;

    address owner = address(this);
    address trader = address(0xBEEF);
    address trader2 = address(0xCAFE);
    address liquidator = address(0xDEAD);

    uint256 constant INITIAL_PRICE = 2000e6; // $2000 with 6 decimals
    uint256 constant USDC_AMOUNT = 10_000e18; // 10k USDC for testing

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        market = new PerpetualMarket(address(usdc), INITIAL_PRICE);

        usdc.mint(trader, USDC_AMOUNT);
        usdc.mint(trader2, USDC_AMOUNT);
        usdc.mint(address(market), 100_000e18);

        vm.prank(trader);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(trader2);
        usdc.approve(address(market), type(uint256).max);
    }

    // ─── Open Position Tests ────────────────────────────────────────────

    function test_openLongPosition() public {
        uint256 size = 1e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        (address t, bool isLong, uint256 s, uint256 c) = market.getPositionCore(posId);
        (uint256 ep, , bool isOpen) = market.getPositionMeta(posId);

        assertEq(t, trader);
        assertTrue(isLong);
        assertEq(s, size);
        assertEq(c, collateral);
        assertEq(ep, INITIAL_PRICE);
        assertTrue(isOpen);
        assertEq(market.totalLongOI(), size);
    }

    function test_openShortPosition() public {
        uint256 size = 1e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(false, size, collateral, 10);

        (address t, bool isLong, uint256 s, uint256 c) = market.getPositionCore(posId);
        (uint256 ep, , bool isOpen) = market.getPositionMeta(posId);

        assertEq(t, trader);
        assertFalse(isLong);
        assertEq(s, size);
        assertEq(c, collateral);
        assertEq(ep, INITIAL_PRICE);
        assertTrue(isOpen);
        assertEq(market.totalShortOI(), size);
    }

    // ─── Close Position Tests ───────────────────────────────────────────

    function test_closeWithProfit_longPriceUp() public {
        uint256 size = 1e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        market.setPrice(2200e6);

        uint256 balBefore = usdc.balanceOf(trader);

        vm.prank(trader);
        market.closePosition(posId);

        uint256 balAfter = usdc.balanceOf(trader);

        assertEq(balAfter - balBefore, 1200e18);
    }

    function test_closeWithLoss_longPriceDown() public {
        uint256 size = 1e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        market.setPrice(1800e6);

        uint256 balBefore = usdc.balanceOf(trader);

        vm.prank(trader);
        market.closePosition(posId);

        uint256 balAfter = usdc.balanceOf(trader);

        assertEq(balAfter - balBefore, 800e18);
    }

    // ─── Liquidation Tests ──────────────────────────────────────────────

    function test_liquidation_belowThreshold() public {
        uint256 size = 5e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        // Set stored price to trigger liquidation
        market.setPrice(1850e6);

        uint256 insuranceBefore = market.insuranceFund();

        vm.prank(liquidator);
        market.liquidate(posId);

        (, , , bool isOpen) = _getMeta(posId);
        assertFalse(isOpen);

        assertEq(market.insuranceFund() - insuranceBefore, 25e18);
    }

    function test_liquidation_revert_healthy() public {
        uint256 size = 1e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        // currentPrice is still INITIAL_PRICE, position is healthy
        vm.prank(liquidator);
        vm.expectRevert(PerpetualMarket.PositionHealthy.selector);
        market.liquidate(posId);
    }

    // ─── Add Collateral Test ────────────────────────────────────────────

    function test_addCollateral() public {
        uint256 size = 1e18;
        uint256 collateral = 500e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        uint256 addAmount = 200e18;
        vm.prank(trader);
        market.addCollateral(posId, addAmount);

        (, , , uint256 c) = market.getPositionCore(posId);
        assertEq(c, collateral + addAmount);
    }

    // ─── Max Leverage Test ──────────────────────────────────────────────

    function test_revert_exceedsMaxLeverage() public {
        vm.prank(trader);
        vm.expectRevert(PerpetualMarket.ExceedsMaxLeverage.selector);
        market.openPosition(true, 1e18, 50e18, 25);
    }

    function test_revert_exceedsMaxLeverage_actualLeverage() public {
        vm.prank(trader);
        vm.expectRevert(PerpetualMarket.ExceedsMaxLeverage.selector);
        market.openPosition(true, 1e18, 150e18, 10);
    }

    // ─── Funding Rate Test ──────────────────────────────────────────────

    function test_fundingRate() public {
        assertEq(market.getFundingRate(), 0);

        vm.prank(trader);
        market.openPosition(true, 1e18, 1000e18, 10);
        assertEq(market.getFundingRate(), 100);

        vm.prank(trader2);
        market.openPosition(false, 1e18, 1000e18, 10);
        assertEq(market.getFundingRate(), 0);
    }

    // ─── Insurance Fund Test ────────────────────────────────────────────

    function test_insuranceFundReceivesPenalty() public {
        uint256 size = 5e18;
        uint256 collateral = 1000e18;

        vm.prank(trader);
        uint256 posId = market.openPosition(true, size, collateral, 10);

        market.setPrice(1850e6);

        assertEq(market.insuranceFund(), 0);

        vm.prank(liquidator);
        market.liquidate(posId);

        assertEq(market.insuranceFund(), 25e18);
    }

    // ─── Authorization Tests ────────────────────────────────────────────

    function test_revert_unauthorizedClose() public {
        vm.prank(trader);
        uint256 posId = market.openPosition(true, 1e18, 1000e18, 10);

        vm.prank(trader2);
        vm.expectRevert(PerpetualMarket.Unauthorized.selector);
        market.closePosition(posId);
    }

    function test_revert_doubleClose() public {
        vm.prank(trader);
        uint256 posId = market.openPosition(true, 1e18, 1000e18, 10);

        vm.prank(trader);
        market.closePosition(posId);

        vm.prank(trader);
        vm.expectRevert(PerpetualMarket.PositionNotOpen.selector);
        market.closePosition(posId);
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _getMeta(uint256 posId) internal view returns (uint256 ep, uint256 lft, uint256 dummy, bool isOpen) {
        (ep, lft, isOpen) = market.getPositionMeta(posId);
        dummy = 0;
    }
}

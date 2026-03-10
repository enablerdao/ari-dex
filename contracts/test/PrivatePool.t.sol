// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PrivatePool} from "../src/PrivatePool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PrivatePoolTest is Test {
    PrivatePool public pool;
    MockERC20 public usdc;
    MockERC20 public weth;

    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie"); // not whitelisted

    uint256 public poolId;

    function setUp() public {
        vm.startPrank(deployer);
        pool = new PrivatePool();
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped ETH", "WETH");

        // Create pool: min trade 10_000, fee 30 bps (0.30%)
        poolId = pool.createPool(address(usdc), address(weth), 10_000e18, 30);

        // Whitelist alice and bob
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        pool.addWhitelist(poolId, accounts);
        vm.stopPrank();

        // Fund LPs
        usdc.mint(alice, 1_000_000e18);
        weth.mint(alice, 1_000e18);
        usdc.mint(bob, 1_000_000e18);
        weth.mint(bob, 1_000e18);
        usdc.mint(charlie, 1_000_000e18);
        weth.mint(charlie, 1_000e18);
    }

    // ─── Pool Creation ──────────────────────────────────────────────────

    function test_createPool() public view {
        (address t0, address t1, uint256 minTrade, uint256 feeBps, bool active) = pool.pools(poolId);
        assertEq(t0, address(usdc));
        assertEq(t1, address(weth));
        assertEq(minTrade, 10_000e18);
        assertEq(feeBps, 30);
        assertTrue(active);
    }

    // ─── Whitelist Management ───────────────────────────────────────────

    function test_whitelistManagement() public {
        assertTrue(pool.isWhitelisted(poolId, alice));
        assertTrue(pool.isWhitelisted(poolId, bob));
        assertFalse(pool.isWhitelisted(poolId, charlie));

        // Remove bob
        address[] memory toRemove = new address[](1);
        toRemove[0] = bob;
        vm.prank(deployer);
        pool.removeWhitelist(poolId, toRemove);

        assertFalse(pool.isWhitelisted(poolId, bob));
    }

    // ─── Deposit & Shares ───────────────────────────────────────────────

    function test_depositAndShareCalculation() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);

        // First deposit: shares = sqrt(100_000 * 100) = sqrt(10_000_000) = 3162 (approx)
        uint256 sharesMinted = pool.deposit(poolId, 100_000e18, 100e18);
        assertTrue(sharesMinted > 0, "Should mint shares");

        uint256 aliceShares = pool.shares(poolId, alice);
        assertEq(aliceShares, sharesMinted);
        vm.stopPrank();

        // Verify reserves
        (uint256 r0, uint256 r1, uint256 totalShares) = pool.poolStates(poolId);
        assertEq(r0, 100_000e18);
        assertEq(r1, 100e18);
        assertEq(totalShares, sharesMinted);
    }

    // ─── Swap by Whitelisted Trader ─────────────────────────────────────

    function test_swapByWhitelistedTrader() public {
        // Alice deposits liquidity
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        pool.deposit(poolId, 100_000e18, 100e18);
        vm.stopPrank();

        // Bob swaps 10_000 USDC -> WETH
        vm.startPrank(bob);
        usdc.approve(address(pool), type(uint256).max);
        uint256 wethBefore = weth.balanceOf(bob);
        uint256 amountOut = pool.swap(poolId, address(usdc), 10_000e18, 0);
        uint256 wethAfter = weth.balanceOf(bob);
        vm.stopPrank();

        assertTrue(amountOut > 0, "Should receive WETH");
        assertEq(wethAfter - wethBefore, amountOut, "Balance should increase by amountOut");
    }

    // ─── Swap Revert: Non-Whitelisted ───────────────────────────────────

    function test_swapRevertNonWhitelisted() public {
        // Deposit first
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        pool.deposit(poolId, 100_000e18, 100e18);
        vm.stopPrank();

        // Charlie is not whitelisted
        vm.startPrank(charlie);
        usdc.approve(address(pool), type(uint256).max);
        vm.expectRevert(PrivatePool.NotWhitelisted.selector);
        pool.swap(poolId, address(usdc), 10_000e18, 0);
        vm.stopPrank();
    }

    // ─── Swap Revert: Below Min Trade Size ──────────────────────────────

    function test_swapRevertBelowMinTradeSize() public {
        // Deposit first
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        pool.deposit(poolId, 100_000e18, 100e18);
        vm.stopPrank();

        // Bob tries to swap less than minTradeSize
        vm.startPrank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.expectRevert(PrivatePool.BelowMinTradeSize.selector);
        pool.swap(poolId, address(usdc), 1_000e18, 0); // 1k < 10k min
        vm.stopPrank();
    }

    // ─── Withdraw Proportional ──────────────────────────────────────────

    function test_withdrawProportional() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        uint256 sharesMinted = pool.deposit(poolId, 100_000e18, 100e18);

        uint256 usdcBefore = usdc.balanceOf(alice);
        uint256 wethBefore = weth.balanceOf(alice);

        // Withdraw all shares
        (uint256 amt0, uint256 amt1) = pool.withdraw(poolId, sharesMinted);
        vm.stopPrank();

        assertEq(amt0, 100_000e18, "Should get all USDC back");
        assertEq(amt1, 100e18, "Should get all WETH back");
        assertEq(usdc.balanceOf(alice) - usdcBefore, amt0);
        assertEq(weth.balanceOf(alice) - wethBefore, amt1);
        assertEq(pool.shares(poolId, alice), 0);
    }

    // ─── Multiple LPs ───────────────────────────────────────────────────

    function test_multipleLPs() public {
        // Alice deposits
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        uint256 aliceShares = pool.deposit(poolId, 100_000e18, 100e18);
        vm.stopPrank();

        // Bob deposits same ratio
        vm.startPrank(bob);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        uint256 bobShares = pool.deposit(poolId, 100_000e18, 100e18);
        vm.stopPrank();

        // Both should get same shares
        assertEq(aliceShares, bobShares, "Same deposit should yield same shares");

        // Total shares should be double
        (,, uint256 totalShares) = pool.poolStates(poolId);
        assertEq(totalShares, aliceShares + bobShares);

        // Each withdraws half
        vm.prank(alice);
        (uint256 a0, uint256 a1) = pool.withdraw(poolId, aliceShares);
        vm.prank(bob);
        (uint256 b0, uint256 b1) = pool.withdraw(poolId, bobShares);

        assertEq(a0, 100_000e18);
        assertEq(a1, 100e18);
        assertEq(b0, 100_000e18);
        assertEq(b1, 100e18);
    }
}

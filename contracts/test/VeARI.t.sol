// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VeARI} from "../src/VeARI.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract VeARITest is Test {
    VeARI public veAri;
    MockERC20 public ariToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant FOUR_YEARS = 4 * 365 days;

    function setUp() public {
        ariToken = new MockERC20("ARI Token", "ARI");
        veAri = new VeARI(address(ariToken));
    }

    // ─── Lock Tests ─────────────────────────────────────────────────────

    function test_lock() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        (uint256 amount, uint256 end) = veAri.locks(alice);
        assertEq(amount, 1000e18);
        assertEq(end, block.timestamp + ONE_YEAR);
        assertEq(ariToken.balanceOf(address(veAri)), 1000e18);
    }

    function test_lock_max_duration() public {
        _fundAndApprove(alice, 500e18);

        vm.prank(alice);
        veAri.lock(500e18, FOUR_YEARS);

        // With max duration, veARI balance equals locked amount
        uint256 bal = veAri.balanceOf(alice);
        // balance = amount * remaining / MAX_LOCK_DURATION
        // remaining = FOUR_YEARS, so bal = amount
        assertEq(bal, 500e18);
    }

    function test_lock_reverts_zero_amount() public {
        vm.prank(alice);
        vm.expectRevert(VeARI.ZeroAmount.selector);
        veAri.lock(0, ONE_YEAR);
    }

    function test_lock_reverts_too_short() public {
        _fundAndApprove(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(VeARI.LockTooShort.selector);
        veAri.lock(100e18, ONE_YEAR - 1);
    }

    function test_lock_reverts_too_long() public {
        _fundAndApprove(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(VeARI.LockTooLong.selector);
        veAri.lock(100e18, FOUR_YEARS + 1);
    }

    function test_lock_reverts_already_locked() public {
        _fundAndApprove(alice, 200e18);

        vm.prank(alice);
        veAri.lock(100e18, ONE_YEAR);

        vm.prank(alice);
        vm.expectRevert(VeARI.AlreadyLocked.selector);
        veAri.lock(100e18, ONE_YEAR);
    }

    // ─── Balance Decay Tests ────────────────────────────────────────────

    function test_balance_decays_over_time() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, FOUR_YEARS);

        // At lock time: full balance
        uint256 balStart = veAri.balanceOf(alice);
        assertEq(balStart, 1000e18);

        // After 2 years: half balance
        vm.warp(block.timestamp + 2 * ONE_YEAR);
        uint256 balMid = veAri.balanceOf(alice);
        assertEq(balMid, 500e18);

        // After 4 years: zero balance (lock expired)
        vm.warp(block.timestamp + 2 * ONE_YEAR);
        uint256 balEnd = veAri.balanceOf(alice);
        assertEq(balEnd, 0);
    }

    function test_balance_one_year_lock() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        // 1 year lock = 1/4 of max, so balance = 1000 * 1yr / 4yr = 250
        uint256 bal = veAri.balanceOf(alice);
        assertEq(bal, 250e18);
    }

    // ─── Increase Amount Tests ──────────────────────────────────────────

    function test_increase_amount() public {
        _fundAndApprove(alice, 2000e18);

        vm.prank(alice);
        veAri.lock(1000e18, FOUR_YEARS);

        vm.prank(alice);
        veAri.increaseAmount(500e18);

        (uint256 amount,) = veAri.locks(alice);
        assertEq(amount, 1500e18);
        assertEq(ariToken.balanceOf(address(veAri)), 1500e18);
    }

    function test_increase_amount_reverts_no_lock() public {
        vm.prank(alice);
        vm.expectRevert(VeARI.NoExistingLock.selector);
        veAri.increaseAmount(100e18);
    }

    function test_increase_amount_reverts_zero() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        vm.prank(alice);
        vm.expectRevert(VeARI.ZeroAmount.selector);
        veAri.increaseAmount(0);
    }

    function test_increase_amount_reverts_expired() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        vm.warp(block.timestamp + ONE_YEAR);

        vm.prank(alice);
        vm.expectRevert(VeARI.LockExpired.selector);
        veAri.increaseAmount(100e18);
    }

    // ─── Increase Unlock Time Tests ─────────────────────────────────────

    function test_increase_unlock_time() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        uint256 newEnd = block.timestamp + 2 * ONE_YEAR;

        vm.prank(alice);
        veAri.increaseUnlockTime(newEnd);

        (, uint256 end) = veAri.locks(alice);
        assertEq(end, newEnd);
    }

    function test_increase_unlock_time_reverts_too_early() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, 2 * ONE_YEAR);

        // Try setting to before current end
        uint256 earlyEnd = block.timestamp + ONE_YEAR;

        vm.prank(alice);
        vm.expectRevert(VeARI.NewEndTooEarly.selector);
        veAri.increaseUnlockTime(earlyEnd);
    }

    function test_increase_unlock_time_reverts_too_late() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        uint256 tooLate = block.timestamp + FOUR_YEARS + 1;

        vm.prank(alice);
        vm.expectRevert(VeARI.NewEndTooLate.selector);
        veAri.increaseUnlockTime(tooLate);
    }

    // ─── Withdraw Tests ─────────────────────────────────────────────────

    function test_withdraw_after_expiry() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        // Warp past lock end
        vm.warp(block.timestamp + ONE_YEAR);

        vm.prank(alice);
        veAri.withdraw();

        assertEq(ariToken.balanceOf(alice), 1000e18);
        (uint256 amount,) = veAri.locks(alice);
        assertEq(amount, 0);
    }

    function test_withdraw_reverts_before_expiry() public {
        _fundAndApprove(alice, 1000e18);

        vm.prank(alice);
        veAri.lock(1000e18, ONE_YEAR);

        vm.prank(alice);
        vm.expectRevert(VeARI.LockNotExpired.selector);
        veAri.withdraw();
    }

    function test_withdraw_reverts_no_lock() public {
        vm.prank(alice);
        vm.expectRevert(VeARI.NoExistingLock.selector);
        veAri.withdraw();
    }

    // ─── Soulbound Tests ────────────────────────────────────────────────

    function test_transfer_reverts() public {
        vm.prank(alice);
        vm.expectRevert(VeARI.TransferNotAllowed.selector);
        veAri.transfer(bob, 100e18);
    }

    function test_transferFrom_reverts() public {
        vm.prank(alice);
        vm.expectRevert(VeARI.TransferNotAllowed.selector);
        veAri.transferFrom(alice, bob, 100e18);
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _fundAndApprove(address account, uint256 amount) internal {
        ariToken.mint(account, amount);
        vm.prank(account);
        ariToken.approve(address(veAri), amount);
    }
}

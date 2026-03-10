// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SolverRegistry} from "../src/SolverRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SolverRegistryTest is Test {
    SolverRegistry public registry;
    MockERC20 public ariToken;

    address public owner = address(this);
    address public solver1 = makeAddr("solver1");
    address public solver2 = makeAddr("solver2");

    uint256 public constant MIN_STAKE = 100_000e18;

    function setUp() public {
        ariToken = new MockERC20("ARI Token", "ARI");
        registry = new SolverRegistry(address(ariToken));
    }

    // ─── Deployment Tests ───────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(registry.owner(), owner);
        assertEq(address(registry.ariToken()), address(ariToken));
        assertEq(registry.MIN_STAKE(), MIN_STAKE);
        assertEq(registry.COOLDOWN_PERIOD(), 7 days);
    }

    // ─── Register Tests ─────────────────────────────────────────────────

    function test_register() public {
        _fundAndApprove(solver1, MIN_STAKE);

        vm.prank(solver1);
        registry.register(MIN_STAKE);

        assertTrue(registry.isSolver(solver1));
        assertEq(registry.getSolverStake(solver1), MIN_STAKE);
        assertEq(registry.solverCount(), 1);
        assertEq(ariToken.balanceOf(address(registry)), MIN_STAKE);
    }

    function test_register_above_minimum() public {
        uint256 stakeAmount = MIN_STAKE * 2;
        _fundAndApprove(solver1, stakeAmount);

        vm.prank(solver1);
        registry.register(stakeAmount);

        assertTrue(registry.isSolver(solver1));
        assertEq(registry.getSolverStake(solver1), stakeAmount);
    }

    function test_register_reverts_insufficient_stake() public {
        uint256 lowStake = MIN_STAKE - 1;
        _fundAndApprove(solver1, lowStake);

        vm.prank(solver1);
        vm.expectRevert(SolverRegistry.InsufficientStake.selector);
        registry.register(lowStake);
    }

    function test_register_reverts_already_registered() public {
        _fundAndApprove(solver1, MIN_STAKE * 2);

        vm.prank(solver1);
        registry.register(MIN_STAKE);

        vm.prank(solver1);
        vm.expectRevert(SolverRegistry.AlreadyRegistered.selector);
        registry.register(MIN_STAKE);
    }

    // ─── Deregister Tests ───────────────────────────────────────────────

    function test_initiateDeregister() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.prank(solver1);
        registry.initiateDeregister();

        assertFalse(registry.isSolver(solver1));
        // Stake is still locked
        assertEq(registry.getSolverStake(solver1), MIN_STAKE);
    }

    function test_deregister_after_cooldown() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.prank(solver1);
        registry.initiateDeregister();

        // Warp past cooldown
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(solver1);
        registry.deregister();

        assertEq(registry.getSolverStake(solver1), 0);
        assertEq(ariToken.balanceOf(solver1), MIN_STAKE);
    }

    function test_deregister_reverts_cooldown_not_elapsed() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.prank(solver1);
        registry.initiateDeregister();

        // Try to deregister before cooldown
        vm.prank(solver1);
        vm.expectRevert(SolverRegistry.CooldownNotElapsed.selector);
        registry.deregister();
    }

    function test_deregister_reverts_not_initiated() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.prank(solver1);
        vm.expectRevert(SolverRegistry.DeregisterNotInitiated.selector);
        registry.deregister();
    }

    function test_initiateDeregister_reverts_not_registered() public {
        vm.prank(solver1);
        vm.expectRevert(SolverRegistry.NotRegistered.selector);
        registry.initiateDeregister();
    }

    // ─── Slash Tests ────────────────────────────────────────────────────

    function test_slash() public {
        _registerSolver(solver1, MIN_STAKE * 2);

        uint256 slashAmount = MIN_STAKE / 2;
        registry.slash(solver1, slashAmount, "misbehavior");

        assertEq(registry.getSolverStake(solver1), MIN_STAKE * 2 - slashAmount);
        // Slashed tokens go to owner
        assertEq(ariToken.balanceOf(owner), slashAmount);
    }

    function test_slash_deactivates_below_minimum() public {
        _registerSolver(solver1, MIN_STAKE);

        // Slash enough to drop below MIN_STAKE
        registry.slash(solver1, 1, "minor offense");

        assertFalse(registry.isSolver(solver1));
        assertEq(registry.getSolverStake(solver1), MIN_STAKE - 1);
    }

    function test_slash_reverts_unauthorized() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.prank(solver2);
        vm.expectRevert(SolverRegistry.Unauthorized.selector);
        registry.slash(solver1, 1, "nope");
    }

    function test_slash_reverts_exceeds_stake() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.expectRevert(SolverRegistry.SlashExceedsStake.selector);
        registry.slash(solver1, MIN_STAKE + 1, "too much");
    }

    function test_slash_reverts_zero_amount() public {
        _registerSolver(solver1, MIN_STAKE);

        vm.expectRevert(SolverRegistry.ZeroAmount.selector);
        registry.slash(solver1, 0, "zero");
    }

    function test_slash_reverts_not_registered() public {
        vm.expectRevert(SolverRegistry.NotRegistered.selector);
        registry.slash(solver1, 1, "not registered");
    }

    // ─── Ownership Tests ────────────────────────────────────────────────

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), newOwner);
    }

    function test_transferOwnership_reverts_unauthorized() public {
        vm.prank(solver1);
        vm.expectRevert(SolverRegistry.Unauthorized.selector);
        registry.transferOwnership(solver1);
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _fundAndApprove(address account, uint256 amount) internal {
        ariToken.mint(account, amount);
        vm.prank(account);
        ariToken.approve(address(registry), amount);
    }

    function _registerSolver(address solver, uint256 amount) internal {
        _fundAndApprove(solver, amount);
        vm.prank(solver);
        registry.register(amount);
    }
}

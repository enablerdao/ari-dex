// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AriPaymaster} from "../src/AriPaymaster.sol";

contract AriPaymasterTest is Test {
    AriPaymaster public paymaster;

    address public owner = address(this);
    address public settlement = makeAddr("settlement");
    address public alice = makeAddr("alice");

    bytes4 public settleSelector;
    bytes4 public settleBatchSelector;

    function setUp() public {
        paymaster = new AriPaymaster(settlement);

        settleSelector = bytes4(keccak256("settle((address,address,uint256,address,uint256,uint256,uint256),(bytes32,address,uint256,bytes),bytes)"));
        settleBatchSelector = bytes4(keccak256("settleBatch((address,address,uint256,address,uint256,uint256,uint256)[],(bytes32,address,uint256,bytes)[],bytes)"));
    }

    // ─── Deployment Tests ───────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(paymaster.owner(), owner);
        assertTrue(paymaster.whitelistedTargets(settlement));
        assertTrue(paymaster.whitelistedSelectors(settleSelector));
        assertTrue(paymaster.whitelistedSelectors(settleBatchSelector));
        assertEq(paymaster.depositBalance(), 0);
    }

    // ─── Deposit Tests ──────────────────────────────────────────────────

    function test_deposit() public {
        paymaster.deposit{value: 1 ether}();
        assertEq(paymaster.depositBalance(), 1 ether);
    }

    function test_deposit_via_receive() public {
        (bool success,) = address(paymaster).call{value: 0.5 ether}("");
        assertTrue(success);
        assertEq(paymaster.depositBalance(), 0.5 ether);
    }

    function test_deposit_reverts_zero() public {
        vm.expectRevert(AriPaymaster.ZeroAmount.selector);
        paymaster.deposit{value: 0}();
    }

    // ─── Withdraw Tests ─────────────────────────────────────────────────

    function test_withdraw() public {
        paymaster.deposit{value: 2 ether}();

        uint256 balBefore = owner.balance;
        paymaster.withdraw(1 ether);

        assertEq(paymaster.depositBalance(), 1 ether);
        assertEq(owner.balance, balBefore + 1 ether);
    }

    function test_withdraw_reverts_insufficient() public {
        paymaster.deposit{value: 1 ether}();

        vm.expectRevert(AriPaymaster.InsufficientDeposit.selector);
        paymaster.withdraw(2 ether);
    }

    function test_withdraw_reverts_unauthorized() public {
        paymaster.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(AriPaymaster.Unauthorized.selector);
        paymaster.withdraw(1 ether);
    }

    // ─── Validate Tests ─────────────────────────────────────────────────

    function test_validate_settle() public {
        paymaster.deposit{value: 1 ether}();

        // Build calldata starting with settle selector
        bytes memory callData = abi.encodePacked(settleSelector, bytes32(0));

        bool valid = paymaster.validatePaymasterUserOp(alice, settlement, callData);
        assertTrue(valid);
    }

    function test_validate_settleBatch() public {
        paymaster.deposit{value: 1 ether}();

        bytes memory callData = abi.encodePacked(settleBatchSelector, bytes32(0));

        bool valid = paymaster.validatePaymasterUserOp(alice, settlement, callData);
        assertTrue(valid);
    }

    function test_validate_reverts_not_whitelisted_target() public {
        paymaster.deposit{value: 1 ether}();

        address randomTarget = makeAddr("random");
        bytes memory callData = abi.encodePacked(settleSelector, bytes32(0));

        vm.expectRevert(AriPaymaster.OperationNotWhitelisted.selector);
        paymaster.validatePaymasterUserOp(alice, randomTarget, callData);
    }

    function test_validate_reverts_not_whitelisted_selector() public {
        paymaster.deposit{value: 1 ether}();

        bytes4 randomSelector = bytes4(keccak256("randomFunction()"));
        bytes memory callData = abi.encodePacked(randomSelector, bytes32(0));

        vm.expectRevert(AriPaymaster.OperationNotWhitelisted.selector);
        paymaster.validatePaymasterUserOp(alice, settlement, callData);
    }

    function test_validate_reverts_no_deposit() public {
        bytes memory callData = abi.encodePacked(settleSelector, bytes32(0));

        vm.expectRevert(AriPaymaster.InsufficientDeposit.selector);
        paymaster.validatePaymasterUserOp(alice, settlement, callData);
    }

    function test_validate_reverts_short_calldata() public {
        paymaster.deposit{value: 1 ether}();

        bytes memory callData = hex"aabb"; // less than 4 bytes

        vm.expectRevert(AriPaymaster.OperationNotWhitelisted.selector);
        paymaster.validatePaymasterUserOp(alice, settlement, callData);
    }

    // ─── Selector / Target Management Tests ─────────────────────────────

    function test_set_selector() public {
        bytes4 newSelector = bytes4(keccak256("newFunction()"));
        paymaster.setSelector(newSelector, true);
        assertTrue(paymaster.whitelistedSelectors(newSelector));

        paymaster.setSelector(newSelector, false);
        assertFalse(paymaster.whitelistedSelectors(newSelector));
    }

    function test_set_target() public {
        address newTarget = makeAddr("newTarget");
        paymaster.setTarget(newTarget, true);
        assertTrue(paymaster.whitelistedTargets(newTarget));

        paymaster.setTarget(newTarget, false);
        assertFalse(paymaster.whitelistedTargets(newTarget));
    }

    function test_set_selector_reverts_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(AriPaymaster.Unauthorized.selector);
        paymaster.setSelector(bytes4(0), true);
    }

    function test_set_target_reverts_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(AriPaymaster.Unauthorized.selector);
        paymaster.setTarget(alice, true);
    }

    // ─── Ownership Tests ────────────────────────────────────────────────

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        paymaster.transferOwnership(newOwner);
        assertEq(paymaster.owner(), newOwner);
    }

    // Allow this test contract to receive ETH
    receive() external payable {}
}

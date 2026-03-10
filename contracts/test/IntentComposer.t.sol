// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IntentComposer} from "../src/IntentComposer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice A mock target that simulates a swap: burns tokenIn, mints tokenOut
contract MockSwapTarget {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    ) external {
        // Pull tokenIn from caller (IntentComposer)
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // Mint tokenOut to caller
        MockERC20(tokenOut).mint(recipient, amountOut);
    }
}

/// @notice A mock target that always reverts
contract MockFailTarget {
    fallback() external {
        revert("MockFailTarget: always fails");
    }
}

contract IntentComposerTest is Test {
    IntentComposer public composer;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;
    MockSwapTarget public swapTarget;
    MockFailTarget public failTarget;

    address public alice = makeAddr("alice");
    address public solver = makeAddr("solver");

    function setUp() public {
        composer = new IntentComposer();
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        tokenC = new MockERC20("Token C", "TKC");
        swapTarget = new MockSwapTarget();
        failTarget = new MockFailTarget();

        // Fund alice
        tokenA.mint(alice, 1000e18);
        tokenB.mint(alice, 1000e18);
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _makeSwapAction(
        address tIn,
        address tOut,
        uint256 amtIn,
        uint256 minOut,
        uint256 actualOut,
        address recipient
    ) internal view returns (IntentComposer.Action memory) {
        bytes memory data = abi.encodeCall(
            MockSwapTarget.swap,
            (tIn, tOut, amtIn, actualOut, recipient)
        );
        return IntentComposer.Action({
            actionType: IntentComposer.ActionType.Swap,
            target: address(swapTarget),
            tokenIn: tIn,
            tokenOut: tOut,
            amountIn: amtIn,
            minAmountOut: minOut,
            data: data
        });
    }

    // ─── Tests ──────────────────────────────────────────────────────────

    function test_createAndExecuteTwoActions() public {
        // Action 1: swap 100 A -> 90 B
        // Action 2: swap 90 B -> 80 C
        IntentComposer.Action[] memory actions = new IntentComposer.Action[](2);

        actions[0] = _makeSwapAction(
            address(tokenA), address(tokenB), 100e18, 90e18, 90e18, address(composer)
        );
        actions[1] = _makeSwapAction(
            address(tokenB), address(tokenC), 90e18, 80e18, 80e18, address(composer)
        );

        // Alice creates intent
        vm.startPrank(alice);
        uint256 intentId = composer.createComposedIntent(actions, block.timestamp + 1 hours);

        // Alice approves composer to pull tokens
        tokenA.approve(address(composer), type(uint256).max);
        tokenB.approve(address(composer), type(uint256).max);
        vm.stopPrank();

        // Approve composer -> swapTarget for tokenIn transfers
        vm.prank(address(composer));
        tokenA.approve(address(swapTarget), type(uint256).max);
        vm.prank(address(composer));
        tokenB.approve(address(swapTarget), type(uint256).max);

        // Solver executes
        vm.prank(solver);
        composer.executeComposedIntent(intentId);

        // Alice should have received 80 tokenC
        assertEq(tokenC.balanceOf(alice), 80e18, "Alice should receive 80 tokenC");

        // Verify intent is marked executed
        (,,, bool executed) = composer.getComposedIntent(intentId);
        assertTrue(executed);
    }

    function test_atomicRevertIfSecondActionFails() public {
        IntentComposer.Action[] memory actions = new IntentComposer.Action[](2);

        // First action succeeds
        actions[0] = _makeSwapAction(
            address(tokenA), address(tokenB), 100e18, 90e18, 90e18, address(composer)
        );

        // Second action targets the fail contract
        actions[1] = IntentComposer.Action({
            actionType: IntentComposer.ActionType.Swap,
            target: address(failTarget),
            tokenIn: address(tokenB),
            tokenOut: address(tokenC),
            amountIn: 90e18,
            minAmountOut: 80e18,
            data: ""
        });

        vm.startPrank(alice);
        uint256 intentId = composer.createComposedIntent(actions, block.timestamp + 1 hours);
        tokenA.approve(address(composer), type(uint256).max);
        tokenB.approve(address(composer), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(composer));
        tokenA.approve(address(swapTarget), type(uint256).max);

        // Entire transaction reverts
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IntentComposer.ActionFailed.selector, 1));
        composer.executeComposedIntent(intentId);

        // Alice balance unchanged
        assertEq(tokenA.balanceOf(alice), 1000e18);
    }

    function test_cancelBeforeExecution() public {
        IntentComposer.Action[] memory actions = new IntentComposer.Action[](1);
        actions[0] = _makeSwapAction(
            address(tokenA), address(tokenB), 10e18, 9e18, 9e18, address(composer)
        );

        vm.prank(alice);
        uint256 intentId = composer.createComposedIntent(actions, block.timestamp + 1 hours);

        vm.prank(alice);
        composer.cancelComposedIntent(intentId);

        // Cannot execute a cancelled intent
        vm.prank(solver);
        vm.expectRevert(IntentComposer.IntentAlreadyExecuted.selector);
        composer.executeComposedIntent(intentId);
    }

    function test_expiredIntentReverts() public {
        IntentComposer.Action[] memory actions = new IntentComposer.Action[](1);
        actions[0] = _makeSwapAction(
            address(tokenA), address(tokenB), 10e18, 9e18, 9e18, address(composer)
        );

        vm.prank(alice);
        uint256 intentId = composer.createComposedIntent(actions, block.timestamp + 1 hours);

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        vm.prank(solver);
        vm.expectRevert(IntentComposer.IntentExpired.selector);
        composer.executeComposedIntent(intentId);
    }

    function test_unauthorizedCancelReverts() public {
        IntentComposer.Action[] memory actions = new IntentComposer.Action[](1);
        actions[0] = _makeSwapAction(
            address(tokenA), address(tokenB), 10e18, 9e18, 9e18, address(composer)
        );

        vm.prank(alice);
        uint256 intentId = composer.createComposedIntent(actions, block.timestamp + 1 hours);

        // Solver tries to cancel Alice's intent
        vm.prank(solver);
        vm.expectRevert(IntentComposer.Unauthorized.selector);
        composer.cancelComposedIntent(intentId);
    }
}

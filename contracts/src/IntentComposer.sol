// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title IntentComposer
/// @author ARI DEX
/// @notice Chains multiple intent actions atomically. A solver calls
///         `executeComposedIntent` to run every action in sequence;
///         each action's output feeds into the next action's input.
///         If any step fails the entire transaction reverts.
contract IntentComposer {
    using SafeERC20 for IERC20;

    // ─── Enums & Structs ────────────────────────────────────────────────

    enum ActionType { Swap, AddLiquidity, RemoveLiquidity, Stake, Unstake, Bridge }

    struct Action {
        ActionType actionType;
        address target;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes data;
    }

    struct ComposedIntent {
        address owner;
        Action[] actions;
        uint256 deadline;
        bool executed;
    }

    // ─── State ──────────────────────────────────────────────────────────

    uint256 public nextIntentId;
    mapping(uint256 => ComposedIntent) private _intents;

    // ─── Events ─────────────────────────────────────────────────────────

    event ComposedIntentCreated(uint256 indexed intentId, address indexed owner, uint256 actionCount);
    event ComposedIntentExecuted(uint256 indexed intentId, address indexed solver);
    event ComposedIntentCancelled(uint256 indexed intentId);

    // ─── Errors ─────────────────────────────────────────────────────────

    error Unauthorized();
    error IntentAlreadyExecuted();
    error IntentExpired();
    error IntentNotFound();
    error EmptyActions();
    error ActionFailed(uint256 actionIndex);
    error InsufficientOutput(uint256 actionIndex, uint256 received, uint256 minRequired);

    // ─── External Functions ─────────────────────────────────────────────

    function createComposedIntent(
        Action[] calldata actions,
        uint256 deadline
    ) external returns (uint256 intentId) {
        if (actions.length == 0) revert EmptyActions();

        intentId = nextIntentId++;
        ComposedIntent storage ci = _intents[intentId];
        ci.owner = msg.sender;
        ci.deadline = deadline;
        ci.executed = false;

        for (uint256 i; i < actions.length; ++i) {
            ci.actions.push(actions[i]);
        }

        emit ComposedIntentCreated(intentId, msg.sender, actions.length);
    }

    function executeComposedIntent(uint256 intentId) external {
        ComposedIntent storage ci = _intents[intentId];
        if (ci.owner == address(0)) revert IntentNotFound();
        if (ci.executed) revert IntentAlreadyExecuted();
        if (block.timestamp > ci.deadline) revert IntentExpired();

        ci.executed = true;

        uint256 len = ci.actions.length;
        uint256 carryAmount;

        for (uint256 i; i < len; ++i) {
            Action storage action = ci.actions[i];

            uint256 amountIn = (i == 0) ? action.amountIn : carryAmount;

            IERC20(action.tokenIn).safeTransferFrom(ci.owner, address(this), amountIn);

            IERC20(action.tokenIn).approve(action.target, amountIn);

            uint256 balBefore = IERC20(action.tokenOut).balanceOf(address(this));

            (bool success,) = action.target.call(action.data);
            if (!success) revert ActionFailed(i);

            uint256 balAfter = IERC20(action.tokenOut).balanceOf(address(this));
            uint256 received = balAfter - balBefore;

            if (received < action.minAmountOut) {
                revert InsufficientOutput(i, received, action.minAmountOut);
            }

            if (i == len - 1) {
                IERC20(action.tokenOut).safeTransfer(ci.owner, received);
            } else {
                IERC20(action.tokenOut).safeTransfer(ci.owner, received);
            }

            carryAmount = received;
        }

        emit ComposedIntentExecuted(intentId, msg.sender);
    }

    function cancelComposedIntent(uint256 intentId) external {
        ComposedIntent storage ci = _intents[intentId];
        if (ci.owner == address(0)) revert IntentNotFound();
        if (ci.owner != msg.sender) revert Unauthorized();
        if (ci.executed) revert IntentAlreadyExecuted();

        ci.executed = true;

        emit ComposedIntentCancelled(intentId);
    }

    function getComposedIntent(uint256 intentId)
        external
        view
        returns (
            address owner,
            Action[] memory actions,
            uint256 deadline,
            bool executed
        )
    {
        ComposedIntent storage ci = _intents[intentId];
        if (ci.owner == address(0)) revert IntentNotFound();
        return (ci.owner, ci.actions, ci.deadline, ci.executed);
    }
}

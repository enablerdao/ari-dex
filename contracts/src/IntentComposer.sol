// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title IntentComposer
/// @author ARI DEX
/// @notice Chains multiple intent actions atomically. A solver calls
///         `executeComposedIntent` to run every action in sequence;
///         each action's output feeds into the next action's input.
///         If any step fails the entire transaction reverts.
contract IntentComposer {
    // ─── Enums & Structs ────────────────────────────────────────────────

    enum ActionType { Swap, AddLiquidity, RemoveLiquidity, Stake, Unstake, Bridge }

    struct Action {
        ActionType actionType;
        address target;      // contract to call
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes data;          // extra calldata for the target
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

    /// @notice Create a multi-step composed intent
    /// @param actions  Ordered list of actions to execute
    /// @param deadline Unix timestamp after which the intent expires
    /// @return intentId The newly created intent's ID
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

    /// @notice Execute all actions of a composed intent atomically
    /// @dev    The solver calls this. Each action's actual output replaces the
    ///         next action's `amountIn` so outputs chain together.
    /// @param intentId  ID of the intent to execute
    function executeComposedIntent(uint256 intentId) external {
        ComposedIntent storage ci = _intents[intentId];
        if (ci.owner == address(0)) revert IntentNotFound();
        if (ci.executed) revert IntentAlreadyExecuted();
        if (block.timestamp > ci.deadline) revert IntentExpired();

        ci.executed = true;

        uint256 len = ci.actions.length;
        uint256 carryAmount; // output of the previous action

        for (uint256 i; i < len; ++i) {
            Action storage action = ci.actions[i];

            // For subsequent actions, override amountIn with previous output
            uint256 amountIn = (i == 0) ? action.amountIn : carryAmount;

            // Pull tokenIn from intent owner into this contract
            IERC20(action.tokenIn).transferFrom(ci.owner, address(this), amountIn);

            // Approve the target to spend the tokenIn
            IERC20(action.tokenIn).approve(action.target, amountIn);

            // Record balance of tokenOut before the call
            uint256 balBefore = IERC20(action.tokenOut).balanceOf(address(this));

            // Call target with the provided data
            (bool success,) = action.target.call(action.data);
            if (!success) revert ActionFailed(i);

            // Measure how much tokenOut we received
            uint256 balAfter = IERC20(action.tokenOut).balanceOf(address(this));
            uint256 received = balAfter - balBefore;

            if (received < action.minAmountOut) {
                revert InsufficientOutput(i, received, action.minAmountOut);
            }

            // Send tokenOut back to owner (or keep for next step)
            if (i == len - 1) {
                // Last action: send output to intent owner
                IERC20(action.tokenOut).transfer(ci.owner, received);
            } else {
                // Intermediate: send output back to owner so next iteration
                // can pull it via transferFrom
                IERC20(action.tokenOut).transfer(ci.owner, received);
            }

            carryAmount = received;
        }

        emit ComposedIntentExecuted(intentId, msg.sender);
    }

    /// @notice Cancel a composed intent before execution
    /// @param intentId  ID of the intent to cancel
    function cancelComposedIntent(uint256 intentId) external {
        ComposedIntent storage ci = _intents[intentId];
        if (ci.owner == address(0)) revert IntentNotFound();
        if (ci.owner != msg.sender) revert Unauthorized();
        if (ci.executed) revert IntentAlreadyExecuted();

        ci.executed = true; // prevent future execution

        emit ComposedIntentCancelled(intentId);
    }

    /// @notice View details of a composed intent
    /// @param intentId  ID of the intent
    /// @return owner     Owner address
    /// @return actions   List of actions
    /// @return deadline  Expiry timestamp
    /// @return executed  Whether it has been executed/cancelled
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title ConditionalIntent
/// @notice Manages conditional orders: limit, stop-loss, take-profit, and DCA.
///         Tokens are held in escrow and released when trigger conditions are met.
contract ConditionalIntent {
    // ─── Enums ──────────────────────────────────────────────────────────

    enum OrderType { Limit, StopLoss, TakeProfit, DCA }
    enum OrderStatus { Active, Executed, Cancelled, Expired }

    // ─── Structs ────────────────────────────────────────────────────────

    struct ConditionalOrder {
        address owner;
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 minBuyAmount;
        uint256 triggerPrice;    // price threshold (6 decimals, e.g. 3000_000000 = $3000)
        OrderType orderType;
        OrderStatus status;
        uint256 deadline;
        uint256 createdAt;
        // DCA fields
        uint256 totalAmount;     // total DCA amount
        uint256 executedAmount;  // already executed
        uint256 intervalSeconds; // time between DCA executions
        uint256 lastExecutedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────

    /// @notice Auto-incrementing order ID counter
    uint256 public nextOrderId;

    /// @notice Order ID => ConditionalOrder
    mapping(uint256 => ConditionalOrder) public orders;

    /// @notice Owner => list of order IDs
    mapping(address => uint256[]) private _userOrders;

    // ─── Events ─────────────────────────────────────────────────────────

    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        OrderType orderType,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 triggerPrice,
        uint256 deadline
    );

    event OrderExecuted(
        uint256 indexed orderId,
        address indexed owner,
        uint256 sellAmount,
        uint256 currentPrice
    );

    event OrderCancelled(uint256 indexed orderId, address indexed owner);

    // ─── Errors ─────────────────────────────────────────────────────────

    error InvalidDeadline();
    error InvalidAmount();
    error OrderNotActive();
    error OrderExpired();
    error OrderNotExpired();
    error TriggerNotMet();
    error Unauthorized();
    error DCAIntervalNotElapsed();
    error DCAFullyExecuted();
    error NotDCAOrder();

    // ─── External: Order Creation ───────────────────────────────────────

    /// @notice Create a limit order — buy when price <= trigger
    function createLimitOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint256 triggerPrice,
        uint256 deadline
    ) external returns (uint256 orderId) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (sellAmount == 0) revert InvalidAmount();

        orderId = _createOrder(_buildOrder(
            sellToken, buyToken, sellAmount, minBuyAmount,
            triggerPrice, OrderType.Limit, deadline
        ));

        IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
    }

    /// @notice Create a stop-loss order — sell when price <= trigger
    function createStopLoss(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint256 triggerPrice,
        uint256 deadline
    ) external returns (uint256 orderId) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (sellAmount == 0) revert InvalidAmount();

        orderId = _createOrder(_buildOrder(
            sellToken, buyToken, sellAmount, minBuyAmount,
            triggerPrice, OrderType.StopLoss, deadline
        ));

        IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
    }

    /// @notice Create a take-profit order — sell when price >= trigger
    function createTakeProfit(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint256 triggerPrice,
        uint256 deadline
    ) external returns (uint256 orderId) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (sellAmount == 0) revert InvalidAmount();

        orderId = _createOrder(_buildOrder(
            sellToken, buyToken, sellAmount, minBuyAmount,
            triggerPrice, OrderType.TakeProfit, deadline
        ));

        IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
    }

    /// @notice Create a DCA order — periodic buys over time
    /// @param totalAmount Total amount of sellToken to spend across all tranches
    /// @param amountPerExecution Amount of sellToken per tranche
    /// @param intervalSeconds Minimum seconds between executions
    function createDCA(
        address sellToken,
        address buyToken,
        uint256 totalAmount,
        uint256 amountPerExecution,
        uint256 intervalSeconds,
        uint256 deadline
    ) external returns (uint256 orderId) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (totalAmount == 0 || amountPerExecution == 0) revert InvalidAmount();

        ConditionalOrder memory order = _buildOrder(
            sellToken, buyToken, amountPerExecution, 0,
            0, OrderType.DCA, deadline
        );
        order.totalAmount = totalAmount;
        order.intervalSeconds = intervalSeconds;
        orderId = _createOrder(order);

        IERC20(sellToken).transferFrom(msg.sender, address(this), totalAmount);
    }

    // ─── External: Execution ────────────────────────────────────────────

    /// @notice Execute a non-DCA conditional order when trigger conditions are met
    /// @param orderId The order to execute
    /// @param currentPrice Current market price (6 decimals)
    function executeOrder(uint256 orderId, uint256 currentPrice) external {
        ConditionalOrder storage order = orders[orderId];

        if (order.status != OrderStatus.Active) revert OrderNotActive();
        if (block.timestamp > order.deadline) revert OrderExpired();

        // Validate trigger condition based on order type
        if (order.orderType == OrderType.Limit) {
            // Limit: buy when price <= trigger (asset is cheap enough)
            if (currentPrice > order.triggerPrice) revert TriggerNotMet();
        } else if (order.orderType == OrderType.StopLoss) {
            // StopLoss: sell when price <= trigger (price dropped to stop level)
            if (currentPrice > order.triggerPrice) revert TriggerNotMet();
        } else if (order.orderType == OrderType.TakeProfit) {
            // TakeProfit: sell when price >= trigger (price rose to target)
            if (currentPrice < order.triggerPrice) revert TriggerNotMet();
        } else {
            revert NotDCAOrder(); // DCA orders use executeDCA
        }

        order.status = OrderStatus.Executed;

        // Transfer escrowed sellToken to msg.sender (keeper/solver)
        IERC20(order.sellToken).transfer(msg.sender, order.sellAmount);

        emit OrderExecuted(orderId, order.owner, order.sellAmount, currentPrice);
    }

    /// @notice Execute one DCA tranche
    /// @param orderId The DCA order to execute
    /// @param currentPrice Current market price (informational, no trigger check for DCA)
    function executeDCA(uint256 orderId, uint256 currentPrice) external {
        ConditionalOrder storage order = orders[orderId];

        if (order.status != OrderStatus.Active) revert OrderNotActive();
        if (block.timestamp > order.deadline) revert OrderExpired();
        if (order.orderType != OrderType.DCA) revert NotDCAOrder();

        uint256 remaining = order.totalAmount - order.executedAmount;
        if (remaining == 0) revert DCAFullyExecuted();

        // Enforce interval
        if (order.lastExecutedAt != 0 &&
            block.timestamp < order.lastExecutedAt + order.intervalSeconds) {
            revert DCAIntervalNotElapsed();
        }

        // Determine tranche size (min of sellAmount-per-execution and remaining)
        uint256 tranche = order.sellAmount;
        if (tranche > remaining) {
            tranche = remaining;
        }

        order.executedAmount += tranche;
        order.lastExecutedAt = block.timestamp;

        // Mark as fully executed if done
        if (order.executedAmount >= order.totalAmount) {
            order.status = OrderStatus.Executed;
        }

        // Transfer tranche to keeper/solver
        IERC20(order.sellToken).transfer(msg.sender, tranche);

        emit OrderExecuted(orderId, order.owner, tranche, currentPrice);
    }

    // ─── External: Cancellation ─────────────────────────────────────────

    /// @notice Cancel an active order and refund escrowed tokens
    function cancelOrder(uint256 orderId) external {
        ConditionalOrder storage order = orders[orderId];

        if (order.owner != msg.sender) revert Unauthorized();
        if (order.status != OrderStatus.Active) revert OrderNotActive();

        order.status = OrderStatus.Cancelled;

        // Refund remaining tokens
        uint256 refund;
        if (order.orderType == OrderType.DCA) {
            refund = order.totalAmount - order.executedAmount;
        } else {
            refund = order.sellAmount;
        }

        if (refund > 0) {
            IERC20(order.sellToken).transfer(order.owner, refund);
        }

        emit OrderCancelled(orderId, order.owner);
    }

    // ─── External: Views ────────────────────────────────────────────────

    /// @notice Get full order details
    function getOrder(uint256 orderId) external view returns (ConditionalOrder memory) {
        return orders[orderId];
    }

    /// @notice Get all active order IDs for an owner
    function getActiveOrders(address owner) external view returns (uint256[] memory) {
        uint256[] storage allIds = _userOrders[owner];
        uint256 count;

        // First pass: count active orders
        for (uint256 i; i < allIds.length; ++i) {
            if (orders[allIds[i]].status == OrderStatus.Active) {
                ++count;
            }
        }

        // Second pass: collect active order IDs
        uint256[] memory activeIds = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < allIds.length; ++i) {
            if (orders[allIds[i]].status == OrderStatus.Active) {
                activeIds[idx++] = allIds[i];
            }
        }

        return activeIds;
    }

    // ─── Internal ───────────────────────────────────────────────────────

    function _buildOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint256 triggerPrice,
        OrderType orderType,
        uint256 deadline
    ) internal view returns (ConditionalOrder memory) {
        return ConditionalOrder({
            owner: msg.sender,
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            minBuyAmount: minBuyAmount,
            triggerPrice: triggerPrice,
            orderType: orderType,
            status: OrderStatus.Active,
            deadline: deadline,
            createdAt: block.timestamp,
            totalAmount: 0,
            executedAmount: 0,
            intervalSeconds: 0,
            lastExecutedAt: 0
        });
    }

    function _createOrder(
        ConditionalOrder memory order
    ) internal returns (uint256 orderId) {
        orderId = nextOrderId++;
        orders[orderId] = order;
        _userOrders[msg.sender].push(orderId);

        emit OrderCreated(
            orderId, msg.sender, order.orderType,
            order.sellToken, order.buyToken, order.sellAmount,
            order.triggerPrice, order.deadline
        );
    }
}

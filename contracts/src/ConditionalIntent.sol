// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/// @title ConditionalIntent
/// @notice Manages conditional orders: limit, stop-loss, take-profit, and DCA.
///         Tokens are held in escrow and released when trigger conditions are met.
///         Uses an oracle for price data instead of trusting the caller.
contract ConditionalIntent {
    using SafeERC20 for IERC20;

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

    /// @notice Price oracle for fetching current prices
    IPriceOracle public immutable oracle;

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

    // ─── Constructor ────────────────────────────────────────────────────

    constructor(address _oracle) {
        oracle = IPriceOracle(_oracle);
    }

    // ─── External: Order Creation ───────────────────────────────────────

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

        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), sellAmount);
    }

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

        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), sellAmount);
    }

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

        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), sellAmount);
    }

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

        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    // ─── External: Execution ────────────────────────────────────────────

    /// @notice Execute a non-DCA conditional order when trigger conditions are met
    /// @param orderId The order to execute
    function executeOrder(uint256 orderId) external {
        ConditionalOrder storage order = orders[orderId];

        if (order.status != OrderStatus.Active) revert OrderNotActive();
        if (block.timestamp > order.deadline) revert OrderExpired();

        // Get price from oracle instead of trusting the caller
        uint256 currentPrice = oracle.getPrice(order.sellToken);

        // Validate trigger condition based on order type
        if (order.orderType == OrderType.Limit) {
            if (currentPrice > order.triggerPrice) revert TriggerNotMet();
        } else if (order.orderType == OrderType.StopLoss) {
            if (currentPrice > order.triggerPrice) revert TriggerNotMet();
        } else if (order.orderType == OrderType.TakeProfit) {
            if (currentPrice < order.triggerPrice) revert TriggerNotMet();
        } else {
            revert NotDCAOrder();
        }

        order.status = OrderStatus.Executed;

        // Transfer escrowed sellToken to msg.sender (keeper/solver)
        IERC20(order.sellToken).safeTransfer(msg.sender, order.sellAmount);

        emit OrderExecuted(orderId, order.owner, order.sellAmount, currentPrice);
    }

    /// @notice Execute one DCA tranche
    /// @param orderId The DCA order to execute
    function executeDCA(uint256 orderId) external {
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

        // Determine tranche size
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

        // Get current price from oracle for informational event
        uint256 currentPrice;
        try oracle.getPrice(order.sellToken) returns (uint256 p) {
            currentPrice = p;
        } catch {
            currentPrice = 0;
        }

        // Transfer tranche to keeper/solver
        IERC20(order.sellToken).safeTransfer(msg.sender, tranche);

        emit OrderExecuted(orderId, order.owner, tranche, currentPrice);
    }

    // ─── External: Cancellation ─────────────────────────────────────────

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
            IERC20(order.sellToken).safeTransfer(order.owner, refund);
        }

        emit OrderCancelled(orderId, order.owner);
    }

    // ─── External: Views ────────────────────────────────────────────────

    function getOrder(uint256 orderId) external view returns (ConditionalOrder memory) {
        return orders[orderId];
    }

    function getActiveOrders(address _owner) external view returns (uint256[] memory) {
        uint256[] storage allIds = _userOrders[_owner];
        uint256 count;

        for (uint256 i; i < allIds.length; ++i) {
            if (orders[allIds[i]].status == OrderStatus.Active) {
                ++count;
            }
        }

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

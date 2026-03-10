// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CrossChainIntent
/// @author ARI DEX
/// @notice Implements ERC-7683 CrossChainOrder flow for cross-chain intent settlement.
///         Users open orders specifying token swaps across chains; solvers fill them
///         on the destination chain; resolution data is recorded for verification.
contract CrossChainIntent {
    // ─── Structs (ERC-7683 aligned) ─────────────────────────────────────

    /// @notice A cross-chain order following the ERC-7683 CrossChainOrder struct
    struct CrossChainOrder {
        address user;
        uint256 originChainId;
        uint256 destinationChainId;
        address originToken;
        uint256 originAmount;
        address destinationToken;
        uint256 minDestinationAmount;
        uint256 deadline;
        uint256 nonce;
        bytes orderData; // additional solver hints / routing data
    }

    /// @notice Fill data submitted by a solver
    struct FillData {
        address solver;
        uint256 destinationAmount;
        bytes proof; // proof of fill on destination chain
    }

    /// @notice Resolution data for a completed order
    struct Resolution {
        bool filled;
        address solver;
        uint256 destinationAmount;
        uint256 filledTimestamp;
    }

    // ─── State ───────────────────────────────────────────────────────────

    /// @notice Contract owner
    address public owner;

    /// @notice Auto-incrementing order ID
    uint256 public nextOrderId = 1;

    /// @notice Order storage by ID
    mapping(uint256 => CrossChainOrder) public orders;

    /// @notice Resolution storage by order ID
    mapping(uint256 => Resolution) public resolutions;

    /// @notice Track used nonces per user
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when a cross-chain order is opened
    event Open(
        uint256 indexed orderId,
        address indexed user,
        uint256 originChainId,
        uint256 destinationChainId,
        address originToken,
        uint256 originAmount,
        address destinationToken,
        uint256 minDestinationAmount,
        uint256 deadline
    );

    /// @notice Emitted when a solver fills an order
    event Fill(uint256 indexed orderId, address indexed solver, uint256 destinationAmount);

    /// @notice Emitted when resolution data is queried/confirmed
    event Resolve(uint256 indexed orderId, address indexed solver, uint256 destinationAmount);

    // ─── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error OrderExpired();
    error NonceAlreadyUsed();
    error OrderAlreadyFilled();
    error OrderNotFound();
    error InsufficientFillAmount();
    error OrderNotFilled();
    error ZeroAmount();

    // ─── Modifiers ───────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Open a new cross-chain order
    /// @param order The cross-chain order data
    /// @return orderId The ID assigned to this order
    function open(CrossChainOrder calldata order) external returns (uint256 orderId) {
        if (order.originAmount == 0) revert ZeroAmount();
        if (block.timestamp > order.deadline) revert OrderExpired();
        if (usedNonces[order.user][order.nonce]) revert NonceAlreadyUsed();

        usedNonces[order.user][order.nonce] = true;

        orderId = nextOrderId++;

        orders[orderId] = CrossChainOrder({
            user: order.user,
            originChainId: order.originChainId,
            destinationChainId: order.destinationChainId,
            originToken: order.originToken,
            originAmount: order.originAmount,
            destinationToken: order.destinationToken,
            minDestinationAmount: order.minDestinationAmount,
            deadline: order.deadline,
            nonce: order.nonce,
            orderData: order.orderData
        });

        emit Open(
            orderId,
            order.user,
            order.originChainId,
            order.destinationChainId,
            order.originToken,
            order.originAmount,
            order.destinationToken,
            order.minDestinationAmount,
            order.deadline
        );
    }

    /// @notice Fill an order (solver submits fill proof)
    /// @param orderId The order to fill
    /// @param fillData The fill data from the solver
    function fill(uint256 orderId, FillData calldata fillData) external {
        CrossChainOrder storage order = orders[orderId];
        if (order.originAmount == 0) revert OrderNotFound();
        if (block.timestamp > order.deadline) revert OrderExpired();

        Resolution storage res = resolutions[orderId];
        if (res.filled) revert OrderAlreadyFilled();

        if (fillData.destinationAmount < order.minDestinationAmount) {
            revert InsufficientFillAmount();
        }

        res.filled = true;
        res.solver = fillData.solver;
        res.destinationAmount = fillData.destinationAmount;
        res.filledTimestamp = block.timestamp;

        emit Fill(orderId, fillData.solver, fillData.destinationAmount);
    }

    /// @notice Get resolution data for an order
    /// @param orderId The order to resolve
    /// @return res The resolution data
    function resolve(uint256 orderId) external returns (Resolution memory res) {
        res = resolutions[orderId];
        if (!res.filled) revert OrderNotFilled();

        emit Resolve(orderId, res.solver, res.destinationAmount);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get order details
    /// @param orderId The order ID
    /// @return The cross-chain order data
    function getOrder(uint256 orderId) external view returns (CrossChainOrder memory) {
        return orders[orderId];
    }

    /// @notice Get resolution details
    /// @param orderId The order ID
    /// @return The resolution data
    function getResolution(uint256 orderId) external view returns (Resolution memory) {
        return resolutions[orderId];
    }
}

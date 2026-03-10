// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CrossChainIntent
/// @author ARI DEX
/// @notice Implements ERC-7683 CrossChainOrder flow for cross-chain intent settlement.
///         Users open orders specifying token swaps across chains; solvers fill them
///         on the destination chain; resolution data is recorded for verification.
///         Origin tokens are escrowed in the contract until fill or cancellation.
contract CrossChainIntent {
    using SafeERC20 for IERC20;

    // ─── Structs (ERC-7683 aligned) ─────────────────────────────────────

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
        bytes orderData;
    }

    struct FillData {
        address solver;
        uint256 destinationAmount;
        bytes proof;
    }

    struct Resolution {
        bool filled;
        address solver;
        uint256 destinationAmount;
        uint256 filledTimestamp;
    }

    // ─── State ───────────────────────────────────────────────────────────

    address public owner;
    uint256 public nextOrderId = 1;

    mapping(uint256 => CrossChainOrder) public orders;
    mapping(uint256 => Resolution) public resolutions;
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    /// @notice Track whether an order has been cancelled
    mapping(uint256 => bool) public cancelled;

    // ─── Events ──────────────────────────────────────────────────────────

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

    event Fill(uint256 indexed orderId, address indexed solver, uint256 destinationAmount);
    event Resolve(uint256 indexed orderId, address indexed solver, uint256 destinationAmount);
    event Cancel(uint256 indexed orderId, address indexed user);

    // ─── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error OrderExpired();
    error NonceAlreadyUsed();
    error OrderAlreadyFilled();
    error OrderNotFound();
    error InsufficientFillAmount();
    error OrderNotFilled();
    error ZeroAmount();
    error OrderNotExpired();
    error OrderAlreadyCancelled();

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

    /// @notice Open a new cross-chain order, escrowing origin tokens
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

        // Escrow origin tokens from the user
        IERC20(order.originToken).safeTransferFrom(order.user, address(this), order.originAmount);

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

    /// @notice Fill an order — solver provides destination tokens to the user
    function fill(uint256 orderId, FillData calldata fillData) external {
        CrossChainOrder storage order = orders[orderId];
        if (order.originAmount == 0) revert OrderNotFound();
        if (block.timestamp > order.deadline) revert OrderExpired();
        if (cancelled[orderId]) revert OrderAlreadyCancelled();

        Resolution storage res = resolutions[orderId];
        if (res.filled) revert OrderAlreadyFilled();

        if (fillData.destinationAmount < order.minDestinationAmount) {
            revert InsufficientFillAmount();
        }

        res.filled = true;
        res.solver = fillData.solver;
        res.destinationAmount = fillData.destinationAmount;
        res.filledTimestamp = block.timestamp;

        // Solver provides destination tokens to the user
        IERC20(order.destinationToken).safeTransferFrom(
            msg.sender, order.user, fillData.destinationAmount
        );

        // Release escrowed origin tokens to the solver
        IERC20(order.originToken).safeTransfer(fillData.solver, order.originAmount);

        emit Fill(orderId, fillData.solver, fillData.destinationAmount);
    }

    /// @notice Cancel an unfilled order after deadline and return escrowed tokens
    function cancel(uint256 orderId) external {
        CrossChainOrder storage order = orders[orderId];
        if (order.originAmount == 0) revert OrderNotFound();
        if (order.user != msg.sender) revert Unauthorized();
        if (block.timestamp <= order.deadline) revert OrderNotExpired();
        if (cancelled[orderId]) revert OrderAlreadyCancelled();

        Resolution storage res = resolutions[orderId];
        if (res.filled) revert OrderAlreadyFilled();

        cancelled[orderId] = true;

        // Return escrowed tokens to the user
        IERC20(order.originToken).safeTransfer(order.user, order.originAmount);

        emit Cancel(orderId, order.user);
    }

    /// @notice Get resolution data for an order
    function resolve(uint256 orderId) external returns (Resolution memory res) {
        res = resolutions[orderId];
        if (!res.filled) revert OrderNotFilled();

        emit Resolve(orderId, res.solver, res.destinationAmount);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    function getOrder(uint256 orderId) external view returns (CrossChainOrder memory) {
        return orders[orderId];
    }

    function getResolution(uint256 orderId) external view returns (Resolution memory) {
        return resolutions[orderId];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SolverRegistry
/// @author ARI DEX
/// @notice Registry for solvers who stake $ARI tokens to participate in intent settlement.
///         Solvers must stake a minimum amount to be eligible. A 7-day cooldown applies
///         to unstaking. The owner can slash misbehaving solvers.
contract SolverRegistry {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────────────

    uint256 public constant MIN_STAKE = 100_000e18;
    uint256 public constant COOLDOWN_PERIOD = 7 days;

    // ─── State ───────────────────────────────────────────────────────────

    address public owner;
    IERC20 public immutable ariToken;

    struct SolverInfo {
        uint256 stakedAmount;
        bool isActive;
        uint256 deregisterTimestamp;
    }

    mapping(address => SolverInfo) public solvers;
    address[] private _solverList;

    // ─── Events ──────────────────────────────────────────────────────────

    event SolverRegistered(address indexed solver, uint256 amount);
    event DeregisterInitiated(address indexed solver, uint256 unlockTime);
    event SolverDeregistered(address indexed solver, uint256 amount);
    event SolverSlashed(address indexed solver, uint256 amount, string reason);

    // ─── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error InsufficientStake();
    error AlreadyRegistered();
    error NotRegistered();
    error CooldownNotElapsed();
    error DeregisterNotInitiated();
    error SlashExceedsStake();
    error ZeroAmount();

    // ─── Modifiers ───────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────

    constructor(address _ariToken) {
        owner = msg.sender;
        ariToken = IERC20(_ariToken);
    }

    // ─── External Functions ──────────────────────────────────────────────

    function register(uint256 amount) external {
        if (amount < MIN_STAKE) revert InsufficientStake();
        if (solvers[msg.sender].isActive) revert AlreadyRegistered();

        ariToken.safeTransferFrom(msg.sender, address(this), amount);

        solvers[msg.sender] = SolverInfo({
            stakedAmount: amount,
            isActive: true,
            deregisterTimestamp: 0
        });

        _solverList.push(msg.sender);

        emit SolverRegistered(msg.sender, amount);
    }

    function initiateDeregister() external {
        SolverInfo storage info = solvers[msg.sender];
        if (!info.isActive) revert NotRegistered();

        info.deregisterTimestamp = block.timestamp + COOLDOWN_PERIOD;
        info.isActive = false;

        emit DeregisterInitiated(msg.sender, info.deregisterTimestamp);
    }

    function deregister() external {
        SolverInfo storage info = solvers[msg.sender];
        if (info.deregisterTimestamp == 0) revert DeregisterNotInitiated();
        if (block.timestamp < info.deregisterTimestamp) revert CooldownNotElapsed();

        uint256 amount = info.stakedAmount;
        info.stakedAmount = 0;
        info.deregisterTimestamp = 0;

        ariToken.safeTransfer(msg.sender, amount);

        emit SolverDeregistered(msg.sender, amount);
    }

    function slash(address solver, uint256 amount, string calldata reason) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        SolverInfo storage info = solvers[solver];
        if (info.stakedAmount == 0) revert NotRegistered();
        if (amount > info.stakedAmount) revert SlashExceedsStake();

        info.stakedAmount -= amount;

        if (info.stakedAmount < MIN_STAKE) {
            info.isActive = false;
        }

        ariToken.safeTransfer(owner, amount);

        emit SolverSlashed(solver, amount, reason);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    function isSolver(address solver) external view returns (bool) {
        return solvers[solver].isActive;
    }

    function getSolverStake(address solver) external view returns (uint256) {
        return solvers[solver].stakedAmount;
    }

    function solverCount() external view returns (uint256) {
        return _solverList.length;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}

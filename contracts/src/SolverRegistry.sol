// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title SolverRegistry
/// @author ARI DEX
/// @notice Registry for solvers who stake $ARI tokens to participate in intent settlement.
///         Solvers must stake a minimum amount to be eligible. A 7-day cooldown applies
///         to unstaking. The owner can slash misbehaving solvers.
contract SolverRegistry {
    // ─── Constants ───────────────────────────────────────────────────────

    /// @notice Minimum stake required to register as a solver (100,000 $ARI)
    uint256 public constant MIN_STAKE = 100_000e18;

    /// @notice Cooldown period before unstaking completes (7 days)
    uint256 public constant COOLDOWN_PERIOD = 7 days;

    // ─── State ───────────────────────────────────────────────────────────

    /// @notice Contract owner (can slash solvers)
    address public owner;

    /// @notice The $ARI ERC-20 token used for staking
    IERC20 public immutable ariToken;

    /// @notice Information about a registered solver
    struct SolverInfo {
        uint256 stakedAmount;
        bool isActive;
        uint256 deregisterTimestamp; // 0 if not deregistering
    }

    /// @notice Mapping from solver address to their info
    mapping(address => SolverInfo) public solvers;

    /// @notice Array of all registered solver addresses
    address[] private _solverList;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when a solver registers by staking tokens
    /// @param solver  Address of the solver
    /// @param amount  Amount staked
    event SolverRegistered(address indexed solver, uint256 amount);

    /// @notice Emitted when a solver initiates deregistration
    /// @param solver  Address of the solver
    /// @param unlockTime  Timestamp when tokens can be withdrawn
    event DeregisterInitiated(address indexed solver, uint256 unlockTime);

    /// @notice Emitted when a solver completes deregistration and withdraws stake
    /// @param solver  Address of the solver
    /// @param amount  Amount returned
    event SolverDeregistered(address indexed solver, uint256 amount);

    /// @notice Emitted when a solver is slashed for misbehavior
    /// @param solver  Address of the slashed solver
    /// @param amount  Amount slashed
    /// @param reason  Human-readable reason for the slash
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

    /// @notice Deploy the SolverRegistry with the $ARI token address
    /// @param _ariToken  Address of the $ARI ERC-20 token
    constructor(address _ariToken) {
        owner = msg.sender;
        ariToken = IERC20(_ariToken);
    }

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Register as a solver by staking $ARI tokens
    /// @param amount  Amount of $ARI to stake (must be >= MIN_STAKE)
    function register(uint256 amount) external {
        if (amount < MIN_STAKE) revert InsufficientStake();
        if (solvers[msg.sender].isActive) revert AlreadyRegistered();

        // Transfer $ARI from solver to this contract
        ariToken.transferFrom(msg.sender, address(this), amount);

        solvers[msg.sender] = SolverInfo({
            stakedAmount: amount,
            isActive: true,
            deregisterTimestamp: 0
        });

        _solverList.push(msg.sender);

        emit SolverRegistered(msg.sender, amount);
    }

    /// @notice Initiate deregistration (starts cooldown)
    function initiateDeregister() external {
        SolverInfo storage info = solvers[msg.sender];
        if (!info.isActive) revert NotRegistered();

        info.deregisterTimestamp = block.timestamp + COOLDOWN_PERIOD;
        info.isActive = false;

        emit DeregisterInitiated(msg.sender, info.deregisterTimestamp);
    }

    /// @notice Complete deregistration after cooldown and withdraw staked tokens
    function deregister() external {
        SolverInfo storage info = solvers[msg.sender];
        if (info.deregisterTimestamp == 0) revert DeregisterNotInitiated();
        if (block.timestamp < info.deregisterTimestamp) revert CooldownNotElapsed();

        uint256 amount = info.stakedAmount;
        info.stakedAmount = 0;
        info.deregisterTimestamp = 0;

        ariToken.transfer(msg.sender, amount);

        emit SolverDeregistered(msg.sender, amount);
    }

    /// @notice Slash a solver's stake for misbehavior
    /// @param solver  Address of the solver to slash
    /// @param amount  Amount of $ARI to slash
    /// @param reason  Reason for the slash
    function slash(address solver, uint256 amount, string calldata reason) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        SolverInfo storage info = solvers[solver];
        if (info.stakedAmount == 0) revert NotRegistered();
        if (amount > info.stakedAmount) revert SlashExceedsStake();

        info.stakedAmount -= amount;

        // If stake drops below minimum, deactivate the solver
        if (info.stakedAmount < MIN_STAKE) {
            info.isActive = false;
        }

        // Transfer slashed tokens to owner (treasury)
        ariToken.transfer(owner, amount);

        emit SolverSlashed(solver, amount, reason);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Check if an address is an active solver
    /// @param solver  Address to check
    /// @return True if the address is a registered and active solver
    function isSolver(address solver) external view returns (bool) {
        return solvers[solver].isActive;
    }

    /// @notice Get the stake amount for a solver
    /// @param solver  Address to query
    /// @return The amount of $ARI currently staked
    function getSolverStake(address solver) external view returns (uint256) {
        return solvers[solver].stakedAmount;
    }

    /// @notice Get the total number of registered solvers (including inactive)
    /// @return Count of solvers
    function solverCount() external view returns (uint256) {
        return _solverList.length;
    }

    /// @notice Transfer contract ownership
    /// @param newOwner  New owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}

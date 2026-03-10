// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title VeARI
/// @author ARI DEX
/// @notice Vote-escrowed ARI. Lock ARI tokens for 1-4 years to receive
///         non-transferable veARI voting power that decays linearly over time.
contract VeARI {
    // ─── Constants ───────────────────────────────────────────────────────

    /// @notice Minimum lock duration: 1 year
    uint256 public constant MIN_LOCK_DURATION = 365 days;

    /// @notice Maximum lock duration: 4 years
    uint256 public constant MAX_LOCK_DURATION = 4 * 365 days;

    // ─── State ───────────────────────────────────────────────────────────

    /// @notice The ARI ERC-20 token
    IERC20 public immutable ariToken;

    /// @notice Lock data per user
    struct Lock {
        uint256 amount;
        uint256 end;
    }

    /// @notice Mapping from address to their lock
    mapping(address => Lock) public locks;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when tokens are locked
    event Locked(address indexed user, uint256 amount, uint256 end);

    /// @notice Emitted when more tokens are added to an existing lock
    event AmountIncreased(address indexed user, uint256 addedAmount, uint256 totalAmount);

    /// @notice Emitted when the lock duration is extended
    event UnlockTimeIncreased(address indexed user, uint256 newEnd);

    /// @notice Emitted when tokens are withdrawn after lock expiry
    event Withdrawn(address indexed user, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────────

    error ZeroAmount();
    error LockTooShort();
    error LockTooLong();
    error LockNotExpired();
    error NoExistingLock();
    error LockExpired();
    error NewEndTooEarly();
    error NewEndTooLate();
    error AlreadyLocked();
    error TransferNotAllowed();

    // ─── Constructor ─────────────────────────────────────────────────────

    /// @notice Deploy VeARI with the ARI token address
    /// @param _ariToken Address of the ARI ERC-20 token
    constructor(address _ariToken) {
        ariToken = IERC20(_ariToken);
    }

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Lock ARI tokens for a specified duration
    /// @param amount Amount of ARI to lock
    /// @param duration Lock duration in seconds (1-4 years)
    function lock(uint256 amount, uint256 duration) external {
        if (amount == 0) revert ZeroAmount();
        if (duration < MIN_LOCK_DURATION) revert LockTooShort();
        if (duration > MAX_LOCK_DURATION) revert LockTooLong();
        if (locks[msg.sender].amount != 0) revert AlreadyLocked();

        uint256 end = block.timestamp + duration;

        locks[msg.sender] = Lock({amount: amount, end: end});

        ariToken.transferFrom(msg.sender, address(this), amount);

        emit Locked(msg.sender, amount, end);
    }

    /// @notice Add more ARI to an existing lock (same unlock time)
    /// @param amount Additional ARI to add
    function increaseAmount(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NoExistingLock();
        if (block.timestamp >= userLock.end) revert LockExpired();

        userLock.amount += amount;

        ariToken.transferFrom(msg.sender, address(this), amount);

        emit AmountIncreased(msg.sender, amount, userLock.amount);
    }

    /// @notice Extend the lock duration
    /// @param newEnd New unlock timestamp (must be later than current end, at most 4 years from now)
    function increaseUnlockTime(uint256 newEnd) external {
        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NoExistingLock();
        if (block.timestamp >= userLock.end) revert LockExpired();
        if (newEnd <= userLock.end) revert NewEndTooEarly();
        if (newEnd > block.timestamp + MAX_LOCK_DURATION) revert NewEndTooLate();

        userLock.end = newEnd;

        emit UnlockTimeIncreased(msg.sender, newEnd);
    }

    /// @notice Withdraw ARI after lock has expired
    function withdraw() external {
        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NoExistingLock();
        if (block.timestamp < userLock.end) revert LockNotExpired();

        uint256 amount = userLock.amount;
        userLock.amount = 0;
        userLock.end = 0;

        ariToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Returns the current veARI balance (decaying linearly)
    /// @param account Address to query
    /// @return Current veARI balance
    function balanceOf(address account) external view returns (uint256) {
        Lock memory userLock = locks[account];
        if (userLock.amount == 0 || block.timestamp >= userLock.end) {
            return 0;
        }

        uint256 remaining = userLock.end - block.timestamp;
        return (userLock.amount * remaining) / MAX_LOCK_DURATION;
    }

    // ─── Soulbound: disable transfers ────────────────────────────────────

    /// @notice veARI is non-transferable (soulbound)
    function transfer(address, uint256) external pure returns (bool) {
        revert TransferNotAllowed();
    }

    /// @notice veARI is non-transferable (soulbound)
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert TransferNotAllowed();
    }
}

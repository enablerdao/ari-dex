// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title VeARI
/// @author ARI DEX
/// @notice Vote-escrowed ARI. Lock ARI tokens for 1-4 years to receive
///         non-transferable veARI voting power that decays linearly over time.
contract VeARI {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────────────

    uint256 public constant MIN_LOCK_DURATION = 365 days;
    uint256 public constant MAX_LOCK_DURATION = 4 * 365 days;

    // ─── State ───────────────────────────────────────────────────────────

    IERC20 public immutable ariToken;

    struct Lock {
        uint256 amount;
        uint256 end;
    }

    mapping(address => Lock) public locks;

    // ─── Events ──────────────────────────────────────────────────────────

    event Locked(address indexed user, uint256 amount, uint256 end);
    event AmountIncreased(address indexed user, uint256 addedAmount, uint256 totalAmount);
    event UnlockTimeIncreased(address indexed user, uint256 newEnd);
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

    constructor(address _ariToken) {
        ariToken = IERC20(_ariToken);
    }

    // ─── External Functions ──────────────────────────────────────────────

    function lock(uint256 amount, uint256 duration) external {
        if (amount == 0) revert ZeroAmount();
        if (duration < MIN_LOCK_DURATION) revert LockTooShort();
        if (duration > MAX_LOCK_DURATION) revert LockTooLong();
        if (locks[msg.sender].amount != 0) revert AlreadyLocked();

        uint256 end = block.timestamp + duration;

        locks[msg.sender] = Lock({amount: amount, end: end});

        ariToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(msg.sender, amount, end);
    }

    function increaseAmount(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NoExistingLock();
        if (block.timestamp >= userLock.end) revert LockExpired();

        userLock.amount += amount;

        ariToken.safeTransferFrom(msg.sender, address(this), amount);

        emit AmountIncreased(msg.sender, amount, userLock.amount);
    }

    function increaseUnlockTime(uint256 newEnd) external {
        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NoExistingLock();
        if (block.timestamp >= userLock.end) revert LockExpired();
        if (newEnd <= userLock.end) revert NewEndTooEarly();
        if (newEnd > block.timestamp + MAX_LOCK_DURATION) revert NewEndTooLate();

        userLock.end = newEnd;

        emit UnlockTimeIncreased(msg.sender, newEnd);
    }

    function withdraw() external {
        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NoExistingLock();
        if (block.timestamp < userLock.end) revert LockNotExpired();

        uint256 amount = userLock.amount;
        userLock.amount = 0;
        userLock.end = 0;

        ariToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    function balanceOf(address account) external view returns (uint256) {
        Lock memory userLock = locks[account];
        if (userLock.amount == 0 || block.timestamp >= userLock.end) {
            return 0;
        }

        uint256 remaining = userLock.end - block.timestamp;
        return (userLock.amount * remaining) / MAX_LOCK_DURATION;
    }

    // ─── Soulbound: disable transfers ────────────────────────────────────

    function transfer(address, uint256) external pure returns (bool) {
        revert TransferNotAllowed();
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert TransferNotAllowed();
    }
}

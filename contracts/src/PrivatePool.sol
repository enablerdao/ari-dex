// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title PrivatePool
/// @author ARI DEX
/// @notice Invitation-only liquidity pool for institutional traders.
///         Uses a simple constant-product AMM (x*y=k) with share-based
///         LP tracking and per-pool whitelist access control.
contract PrivatePool {
    // ─── Structs ────────────────────────────────────────────────────────

    struct PoolConfig {
        address token0;
        address token1;
        uint256 minTradeSize;  // minimum trade amount (in tokenIn units)
        uint256 feeBps;        // fee in basis points (e.g. 30 = 0.30%)
        bool active;
    }

    struct PoolState {
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalShares;
    }

    // ─── State ──────────────────────────────────────────────────────────

    address public owner;
    uint256 public nextPoolId;

    mapping(uint256 => PoolConfig) public pools;
    mapping(uint256 => PoolState) public poolStates;

    /// @notice poolId => user => whitelisted
    mapping(uint256 => mapping(address => bool)) public whitelisted;

    /// @notice poolId => user => LP shares
    mapping(uint256 => mapping(address => uint256)) public shares;

    // ─── Events ─────────────────────────────────────────────────────────

    event PoolCreated(uint256 indexed poolId, address token0, address token1, uint256 minTradeSize, uint256 feeBps);
    event WhitelistAdded(uint256 indexed poolId, address[] accounts);
    event WhitelistRemoved(uint256 indexed poolId, address[] accounts);
    event Deposited(uint256 indexed poolId, address indexed lp, uint256 amount0, uint256 amount1, uint256 sharesMinted);
    event Withdrawn(uint256 indexed poolId, address indexed lp, uint256 shares, uint256 amount0, uint256 amount1);
    event Swapped(uint256 indexed poolId, address indexed trader, address tokenIn, uint256 amountIn, uint256 amountOut);

    // ─── Errors ─────────────────────────────────────────────────────────

    error Unauthorized();
    error PoolNotFound();
    error PoolInactive();
    error NotWhitelisted();
    error BelowMinTradeSize();
    error InvalidTokenPair();
    error ZeroAmount();
    error InsufficientOutput();
    error InsufficientShares();
    error ZeroShares();

    // ─── Modifiers ──────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyWhitelisted(uint256 poolId) {
        if (!whitelisted[poolId][msg.sender]) revert NotWhitelisted();
        _;
    }

    modifier poolExists(uint256 poolId) {
        if (pools[poolId].token0 == address(0)) revert PoolNotFound();
        _;
    }

    modifier poolActive(uint256 poolId) {
        if (!pools[poolId].active) revert PoolInactive();
        _;
    }

    // ─── Constructor ────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── Pool Management ────────────────────────────────────────────────

    /// @notice Create a new private pool
    /// @param token0       First token
    /// @param token1       Second token
    /// @param minTradeSize Minimum trade size in token units
    /// @param feeBps       Fee in basis points
    /// @return poolId      The newly created pool's ID
    function createPool(
        address token0,
        address token1,
        uint256 minTradeSize,
        uint256 feeBps
    ) external onlyOwner returns (uint256 poolId) {
        poolId = nextPoolId++;
        pools[poolId] = PoolConfig({
            token0: token0,
            token1: token1,
            minTradeSize: minTradeSize,
            feeBps: feeBps,
            active: true
        });

        emit PoolCreated(poolId, token0, token1, minTradeSize, feeBps);
    }

    /// @notice Add addresses to pool whitelist
    /// @param poolId    Pool ID
    /// @param accounts  Addresses to whitelist
    function addWhitelist(uint256 poolId, address[] calldata accounts)
        external
        onlyOwner
        poolExists(poolId)
    {
        for (uint256 i; i < accounts.length; ++i) {
            whitelisted[poolId][accounts[i]] = true;
        }
        emit WhitelistAdded(poolId, accounts);
    }

    /// @notice Remove addresses from pool whitelist
    /// @param poolId    Pool ID
    /// @param accounts  Addresses to remove
    function removeWhitelist(uint256 poolId, address[] calldata accounts)
        external
        onlyOwner
        poolExists(poolId)
    {
        for (uint256 i; i < accounts.length; ++i) {
            whitelisted[poolId][accounts[i]] = false;
        }
        emit WhitelistRemoved(poolId, accounts);
    }

    /// @notice Check if an address is whitelisted for a pool
    /// @param poolId   Pool ID
    /// @param account  Address to check
    /// @return         True if whitelisted
    function isWhitelisted(uint256 poolId, address account)
        external
        view
        returns (bool)
    {
        return whitelisted[poolId][account];
    }

    // ─── Liquidity ──────────────────────────────────────────────────────

    /// @notice Deposit liquidity into a pool
    /// @param poolId        Pool ID
    /// @param token0Amount  Amount of token0 to deposit
    /// @param token1Amount  Amount of token1 to deposit
    /// @return sharesMinted Number of LP shares minted
    function deposit(
        uint256 poolId,
        uint256 token0Amount,
        uint256 token1Amount
    )
        external
        poolExists(poolId)
        poolActive(poolId)
        onlyWhitelisted(poolId)
        returns (uint256 sharesMinted)
    {
        if (token0Amount == 0 || token1Amount == 0) revert ZeroAmount();

        PoolConfig storage cfg = pools[poolId];
        PoolState storage state = poolStates[poolId];

        // Transfer tokens in
        IERC20(cfg.token0).transferFrom(msg.sender, address(this), token0Amount);
        IERC20(cfg.token1).transferFrom(msg.sender, address(this), token1Amount);

        // Calculate shares
        if (state.totalShares == 0) {
            // First deposit: shares = sqrt(amount0 * amount1)
            sharesMinted = _sqrt(token0Amount * token1Amount);
        } else {
            // Proportional to existing reserves (use the smaller ratio)
            uint256 shares0 = (token0Amount * state.totalShares) / state.reserve0;
            uint256 shares1 = (token1Amount * state.totalShares) / state.reserve1;
            sharesMinted = shares0 < shares1 ? shares0 : shares1;
        }

        if (sharesMinted == 0) revert ZeroShares();

        // Update state
        state.reserve0 += token0Amount;
        state.reserve1 += token1Amount;
        state.totalShares += sharesMinted;
        shares[poolId][msg.sender] += sharesMinted;

        emit Deposited(poolId, msg.sender, token0Amount, token1Amount, sharesMinted);
    }

    /// @notice Withdraw liquidity proportionally
    /// @param poolId       Pool ID
    /// @param shareAmount  Number of shares to burn
    /// @return amount0     Token0 returned
    /// @return amount1     Token1 returned
    function withdraw(uint256 poolId, uint256 shareAmount)
        external
        poolExists(poolId)
        returns (uint256 amount0, uint256 amount1)
    {
        if (shareAmount == 0) revert ZeroAmount();
        if (shares[poolId][msg.sender] < shareAmount) revert InsufficientShares();

        PoolState storage state = poolStates[poolId];
        PoolConfig storage cfg = pools[poolId];

        // Calculate proportional amounts
        amount0 = (shareAmount * state.reserve0) / state.totalShares;
        amount1 = (shareAmount * state.reserve1) / state.totalShares;

        // Update state
        shares[poolId][msg.sender] -= shareAmount;
        state.totalShares -= shareAmount;
        state.reserve0 -= amount0;
        state.reserve1 -= amount1;

        // Transfer tokens out
        IERC20(cfg.token0).transfer(msg.sender, amount0);
        IERC20(cfg.token1).transfer(msg.sender, amount1);

        emit Withdrawn(poolId, msg.sender, shareAmount, amount0, amount1);
    }

    // ─── Trading ────────────────────────────────────────────────────────

    /// @notice Swap tokens in a private pool
    /// @param poolId       Pool ID
    /// @param tokenIn      Token to sell
    /// @param amountIn     Amount to sell
    /// @param minAmountOut Minimum acceptable output
    /// @return amountOut   Actual output amount
    function swap(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        poolExists(poolId)
        poolActive(poolId)
        onlyWhitelisted(poolId)
        returns (uint256 amountOut)
    {
        PoolConfig storage cfg = pools[poolId];
        PoolState storage state = poolStates[poolId];

        if (amountIn < cfg.minTradeSize) revert BelowMinTradeSize();

        // Determine direction
        bool zeroForOne;
        if (tokenIn == cfg.token0) {
            zeroForOne = true;
        } else if (tokenIn == cfg.token1) {
            zeroForOne = false;
        } else {
            revert InvalidTokenPair();
        }

        // Fee deduction
        uint256 feeAmount = (amountIn * cfg.feeBps) / 10_000;
        uint256 amountInAfterFee = amountIn - feeAmount;

        // Constant product: amountOut = reserveOut * amountInAfterFee / (reserveIn + amountInAfterFee)
        uint256 reserveIn  = zeroForOne ? state.reserve0 : state.reserve1;
        uint256 reserveOut = zeroForOne ? state.reserve1 : state.reserve0;

        amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);

        if (amountOut < minAmountOut) revert InsufficientOutput();

        // Transfer tokenIn from trader
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Update reserves (fee stays in the pool as extra reserve)
        if (zeroForOne) {
            state.reserve0 += amountIn;
            state.reserve1 -= amountOut;
        } else {
            state.reserve1 += amountIn;
            state.reserve0 -= amountOut;
        }

        // Transfer tokenOut to trader
        address tokenOut = zeroForOne ? cfg.token1 : cfg.token0;
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swapped(poolId, msg.sender, tokenIn, amountIn, amountOut);
    }

    // ─── Internal ───────────────────────────────────────────────────────

    /// @notice Integer square root (Babylonian method)
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

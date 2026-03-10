// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PrivatePool
/// @author ARI DEX
/// @notice Invitation-only liquidity pool for institutional traders.
///         Uses a simple constant-product AMM (x*y=k) with share-based
///         LP tracking and per-pool whitelist access control.
contract PrivatePool {
    using SafeERC20 for IERC20;

    // ─── Structs ────────────────────────────────────────────────────────

    struct PoolConfig {
        address token0;
        address token1;
        uint256 minTradeSize;
        uint256 feeBps;
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
    mapping(uint256 => mapping(address => bool)) public whitelisted;
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

    function isWhitelisted(uint256 poolId, address account)
        external
        view
        returns (bool)
    {
        return whitelisted[poolId][account];
    }

    // ─── Liquidity ──────────────────────────────────────────────────────

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

        IERC20(cfg.token0).safeTransferFrom(msg.sender, address(this), token0Amount);
        IERC20(cfg.token1).safeTransferFrom(msg.sender, address(this), token1Amount);

        if (state.totalShares == 0) {
            sharesMinted = _sqrt(token0Amount * token1Amount);
        } else {
            uint256 shares0 = (token0Amount * state.totalShares) / state.reserve0;
            uint256 shares1 = (token1Amount * state.totalShares) / state.reserve1;
            sharesMinted = shares0 < shares1 ? shares0 : shares1;
        }

        if (sharesMinted == 0) revert ZeroShares();

        state.reserve0 += token0Amount;
        state.reserve1 += token1Amount;
        state.totalShares += sharesMinted;
        shares[poolId][msg.sender] += sharesMinted;

        emit Deposited(poolId, msg.sender, token0Amount, token1Amount, sharesMinted);
    }

    function withdraw(uint256 poolId, uint256 shareAmount)
        external
        poolExists(poolId)
        returns (uint256 amount0, uint256 amount1)
    {
        if (shareAmount == 0) revert ZeroAmount();
        if (shares[poolId][msg.sender] < shareAmount) revert InsufficientShares();

        PoolState storage state = poolStates[poolId];
        PoolConfig storage cfg = pools[poolId];

        amount0 = (shareAmount * state.reserve0) / state.totalShares;
        amount1 = (shareAmount * state.reserve1) / state.totalShares;

        shares[poolId][msg.sender] -= shareAmount;
        state.totalShares -= shareAmount;
        state.reserve0 -= amount0;
        state.reserve1 -= amount1;

        IERC20(cfg.token0).safeTransfer(msg.sender, amount0);
        IERC20(cfg.token1).safeTransfer(msg.sender, amount1);

        emit Withdrawn(poolId, msg.sender, shareAmount, amount0, amount1);
    }

    // ─── Trading ────────────────────────────────────────────────────────

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

        bool zeroForOne;
        if (tokenIn == cfg.token0) {
            zeroForOne = true;
        } else if (tokenIn == cfg.token1) {
            zeroForOne = false;
        } else {
            revert InvalidTokenPair();
        }

        uint256 feeAmount = (amountIn * cfg.feeBps) / 10_000;
        uint256 amountInAfterFee = amountIn - feeAmount;

        uint256 reserveIn  = zeroForOne ? state.reserve0 : state.reserve1;
        uint256 reserveOut = zeroForOne ? state.reserve1 : state.reserve0;

        amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);

        if (amountOut < minAmountOut) revert InsufficientOutput();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (zeroForOne) {
            state.reserve0 += amountIn;
            state.reserve1 -= amountOut;
        } else {
            state.reserve1 += amountIn;
            state.reserve0 -= amountOut;
        }

        address tokenOut = zeroForOne ? cfg.token1 : cfg.token0;
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swapped(poolId, msg.sender, tokenIn, amountIn, amountOut);
    }

    // ─── Internal ───────────────────────────────────────────────────────

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

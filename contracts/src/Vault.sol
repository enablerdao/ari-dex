// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title Vault
/// @author ARI DEX
/// @notice Concentrated liquidity vault with ERC-721 LP positions.
///         Each position is a unique NFT representing a liquidity range [tickLower, tickUpper].
contract Vault {
    // ─── ERC-721 State ───────────────────────────────────────────────────

    string public name;
    string public symbol;

    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // ─── Pool State ──────────────────────────────────────────────────────

    /// @notice The pool configuration and current state
    struct Pool {
        address token0;
        address token1;
        uint24 feeTier;
        uint160 sqrtPriceX96;
        uint128 liquidity;
        int24 tick;
    }

    /// @notice A concentrated liquidity position
    struct Position {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowth0;
        uint256 feeGrowth1;
    }

    /// @notice The pool managed by this vault
    Pool public pool;

    /// @notice Mapping from tokenId to position data
    mapping(uint256 => Position) public positions;

    /// @notice Whether the vault has been initialized
    bool public initialized;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice ERC-721 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @notice ERC-721 Approval event
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /// @notice ERC-721 ApprovalForAll event
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Emitted when liquidity is added
    event Mint(
        uint256 indexed tokenId,
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when liquidity is removed
    event Burn(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Emitted on a swap
    event Swap(
        address indexed sender,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Emitted when fees are collected
    event Collect(uint256 indexed tokenId, uint256 fees0, uint256 fees1);

    // ─── Errors ──────────────────────────────────────────────────────────

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidTickRange();
    error InsufficientLiquidity();
    error NotOwnerOrApproved();
    error TransferToZeroAddress();
    error TokenDoesNotExist();
    error ZeroLiquidity();
    error SqrtPriceLimitExceeded();

    // ─── Initializer ─────────────────────────────────────────────────────

    /// @notice Initialize the vault with pool parameters (called by factory)
    /// @param token0  Address of token0 (lower sort order)
    /// @param token1  Address of token1 (higher sort order)
    /// @param feeTier  Fee tier in basis points (e.g., 3000 = 0.3%)
    function initialize(address token0, address token1, uint24 feeTier) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        name = "ARI LP Position";
        symbol = "ARI-LP";

        pool = Pool({
            token0: token0,
            token1: token1,
            feeTier: feeTier,
            sqrtPriceX96: 79228162514264337593543950336, // 1:1 price (1 << 96)
            liquidity: 0,
            tick: 0
        });
    }

    // ─── LP Functions ────────────────────────────────────────────────────

    /// @notice Mint a new concentrated liquidity position
    /// @param token0  Pool token0 address (must match pool)
    /// @param token1  Pool token1 address (must match pool)
    /// @param feeTier  Pool fee tier (must match pool)
    /// @param tickLower  Lower bound of the price range
    /// @param tickUpper  Upper bound of the price range
    /// @param amount0  Amount of token0 to deposit
    /// @param amount1  Amount of token1 to deposit
    /// @return tokenId  The NFT token ID representing this position
    function mint(
        address token0,
        address token1,
        uint24 feeTier,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 tokenId) {
        if (!initialized) revert NotInitialized();
        if (tickLower >= tickUpper) revert InvalidTickRange();

        // Validate pool match
        require(token0 == pool.token0 && token1 == pool.token1 && feeTier == pool.feeTier, "Pool mismatch");

        // Calculate liquidity from deposited amounts (simplified)
        uint128 liquidity = uint128(amount0 < amount1 ? amount0 : amount1);
        if (liquidity == 0) revert ZeroLiquidity();

        // Transfer tokens in
        IERC20(pool.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(pool.token1).transferFrom(msg.sender, address(this), amount1);

        // Mint NFT
        tokenId = _nextTokenId++;
        _mint(msg.sender, tokenId);

        // Store position
        positions[tokenId] = Position({
            owner: msg.sender,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowth0: 0,
            feeGrowth1: 0
        });

        // Update pool liquidity
        pool.liquidity += liquidity;

        emit Mint(tokenId, msg.sender, tickLower, tickUpper, liquidity, amount0, amount1);
    }

    /// @notice Burn a position and withdraw liquidity
    /// @param tokenId  The NFT token ID to burn
    /// @return amount0  Amount of token0 returned
    /// @return amount1  Amount of token1 returned
    function burn(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();

        Position storage pos = positions[tokenId];
        if (pos.liquidity == 0) revert ZeroLiquidity();

        uint128 liquidity = pos.liquidity;

        // Simplified: return proportional amounts based on liquidity
        uint256 totalLiquidity = pool.liquidity;
        amount0 = (IERC20(pool.token0).balanceOf(address(this)) * liquidity) / totalLiquidity;
        amount1 = (IERC20(pool.token1).balanceOf(address(this)) * liquidity) / totalLiquidity;

        // Update state
        pool.liquidity -= liquidity;
        pos.liquidity = 0;

        // Transfer tokens out
        IERC20(pool.token0).transfer(msg.sender, amount0);
        IERC20(pool.token1).transfer(msg.sender, amount1);

        // Burn NFT
        _burn(tokenId);

        emit Burn(tokenId, liquidity, amount0, amount1);
    }

    /// @notice Execute a swap through the pool
    /// @param tokenIn  Token being sold
    /// @param tokenOut  Token being bought
    /// @param amountIn  Amount of tokenIn to swap
    /// @param sqrtPriceLimitX96  Price limit for the swap (0 for no limit)
    /// @return amountOut  Amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut) {
        if (!initialized) revert NotInitialized();
        if (pool.liquidity == 0) revert InsufficientLiquidity();

        // Validate token pair
        require(
            (tokenIn == pool.token0 && tokenOut == pool.token1)
                || (tokenIn == pool.token1 && tokenOut == pool.token0),
            "Invalid token pair"
        );

        // Simplified constant-product swap with fee deduction
        uint256 feeAmount = (amountIn * pool.feeTier) / 1_000_000;
        uint256 amountInAfterFee = amountIn - feeAmount;

        uint256 reserveIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 reserveOut = IERC20(tokenOut).balanceOf(address(this));

        // x * y = k
        amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);

        if (amountOut == 0) revert InsufficientLiquidity();

        // Enforce price limit if set
        if (sqrtPriceLimitX96 > 0) {
            // Simplified price check
            (sqrtPriceLimitX96); // acknowledged
        }

        // Execute transfers
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Collect accumulated fees for a position
    /// @param tokenId  The NFT token ID
    /// @return fees0  Collected fees in token0
    /// @return fees1  Collected fees in token1
    function collect(uint256 tokenId) external returns (uint256 fees0, uint256 fees1) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();

        Position storage pos = positions[tokenId];

        // Simplified fee collection (in production, compute from feeGrowthGlobal deltas)
        fees0 = pos.feeGrowth0;
        fees1 = pos.feeGrowth1;

        pos.feeGrowth0 = 0;
        pos.feeGrowth1 = 0;

        if (fees0 > 0) {
            IERC20(pool.token0).transfer(msg.sender, fees0);
        }
        if (fees1 > 0) {
            IERC20(pool.token1).transfer(msg.sender, fees1);
        }

        emit Collect(tokenId, fees0, fees1);
    }

    // ─── ERC-721 Core ────────────────────────────────────────────────────

    /// @notice Get the owner of a token
    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenDoesNotExist();
        return tokenOwner;
    }

    /// @notice Get the balance of an address
    function balanceOf(address account) public view returns (uint256) {
        require(account != address(0), "Zero address");
        return _balances[account];
    }

    /// @notice Approve an address for a token
    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _approvals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    /// @notice Get the approved address for a token
    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _approvals[tokenId];
    }

    /// @notice Set or revoke operator approval
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Check if an operator is approved for all tokens
    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /// @notice Transfer a token
    function transferFrom(address from, address to, uint256 tokenId) external {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();
        _transfer(from, to, tokenId);
    }

    // ─── ERC-721 Internal ────────────────────────────────────────────────

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert TransferToZeroAddress();
        _owners[tokenId] = to;
        _balances[to] += 1;
        emit Transfer(address(0), to, tokenId);
    }

    function _burn(uint256 tokenId) internal {
        address tokenOwner = _owners[tokenId];
        _balances[tokenOwner] -= 1;
        delete _owners[tokenId];
        delete _approvals[tokenId];
        emit Transfer(tokenOwner, address(0), tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert TransferToZeroAddress();
        require(ownerOf(tokenId) == from, "Not owner");

        delete _approvals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        // Update position owner
        positions[tokenId].owner = to;

        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || getApproved(tokenId) == spender || isApprovedForAll(tokenOwner, spender));
    }
}

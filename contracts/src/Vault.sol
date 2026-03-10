// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Vault
/// @author ARI DEX
/// @notice Concentrated liquidity vault with ERC-721 LP positions.
///         Each position is a unique NFT representing a liquidity range [tickLower, tickUpper].
contract Vault {
    using SafeERC20 for IERC20;

    // ─── ERC-721 State ───────────────────────────────────────────────────

    string public name;
    string public symbol;

    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // ─── Reentrancy Guard ─────────────────────────────────────────────────

    uint256 private _locked = 1;

    // ─── Pool State ──────────────────────────────────────────────────────

    struct Pool {
        address token0;
        address token1;
        uint24 feeTier;
        uint160 sqrtPriceX96;
        uint128 liquidity;
        int24 tick;
    }

    struct Position {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowth0;
        uint256 feeGrowth1;
    }

    Pool public pool;
    mapping(uint256 => Position) public positions;
    bool public initialized;

    // ─── Events ──────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event Mint(
        uint256 indexed tokenId,
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event Burn(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    event Swap(
        address indexed sender,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

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
    error Reentrancy();

    // ─── Modifiers ───────────────────────────────────────────────────────

    modifier nonReentrant() {
        if (_locked == 2) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ─── Initializer ─────────────────────────────────────────────────────

    function initialize(address token0, address token1, uint24 feeTier) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        name = "ARI LP Position";
        symbol = "ARI-LP";

        pool = Pool({
            token0: token0,
            token1: token1,
            feeTier: feeTier,
            sqrtPriceX96: 79228162514264337593543950336,
            liquidity: 0,
            tick: 0
        });
    }

    // ─── LP Functions ────────────────────────────────────────────────────

    function mint(
        address token0,
        address token1,
        uint24 feeTier,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant returns (uint256 tokenId) {
        if (!initialized) revert NotInitialized();
        if (tickLower >= tickUpper) revert InvalidTickRange();

        require(token0 == pool.token0 && token1 == pool.token1 && feeTier == pool.feeTier, "Pool mismatch");

        uint128 liquidity = uint128(amount0 < amount1 ? amount0 : amount1);
        if (liquidity == 0) revert ZeroLiquidity();

        IERC20(pool.token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(pool.token1).safeTransferFrom(msg.sender, address(this), amount1);

        tokenId = _nextTokenId++;
        _mint(msg.sender, tokenId);

        positions[tokenId] = Position({
            owner: msg.sender,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowth0: 0,
            feeGrowth1: 0
        });

        pool.liquidity += liquidity;

        emit Mint(tokenId, msg.sender, tickLower, tickUpper, liquidity, amount0, amount1);
    }

    function burn(uint256 tokenId) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();

        Position storage pos = positions[tokenId];
        if (pos.liquidity == 0) revert ZeroLiquidity();

        uint128 liquidity = pos.liquidity;

        uint256 totalLiquidity = pool.liquidity;
        amount0 = (IERC20(pool.token0).balanceOf(address(this)) * liquidity) / totalLiquidity;
        amount1 = (IERC20(pool.token1).balanceOf(address(this)) * liquidity) / totalLiquidity;

        pool.liquidity -= liquidity;
        pos.liquidity = 0;

        IERC20(pool.token0).safeTransfer(msg.sender, amount0);
        IERC20(pool.token1).safeTransfer(msg.sender, amount1);

        _burn(tokenId);

        emit Burn(tokenId, liquidity, amount0, amount1);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external nonReentrant returns (uint256 amountOut) {
        if (!initialized) revert NotInitialized();
        if (pool.liquidity == 0) revert InsufficientLiquidity();

        require(
            (tokenIn == pool.token0 && tokenOut == pool.token1)
                || (tokenIn == pool.token1 && tokenOut == pool.token0),
            "Invalid token pair"
        );

        uint256 feeAmount = (amountIn * pool.feeTier) / 1_000_000;
        uint256 amountInAfterFee = amountIn - feeAmount;

        uint256 reserveIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 reserveOut = IERC20(tokenOut).balanceOf(address(this));

        amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);

        if (amountOut == 0) revert InsufficientLiquidity();

        if (sqrtPriceLimitX96 > 0) {
            (sqrtPriceLimitX96);
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function collect(uint256 tokenId) external nonReentrant returns (uint256 fees0, uint256 fees1) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();

        Position storage pos = positions[tokenId];

        fees0 = pos.feeGrowth0;
        fees1 = pos.feeGrowth1;

        pos.feeGrowth0 = 0;
        pos.feeGrowth1 = 0;

        if (fees0 > 0) {
            IERC20(pool.token0).safeTransfer(msg.sender, fees0);
        }
        if (fees1 > 0) {
            IERC20(pool.token1).safeTransfer(msg.sender, fees1);
        }

        emit Collect(tokenId, fees0, fees1);
    }

    // ─── ERC-721 Core ────────────────────────────────────────────────────

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenDoesNotExist();
        return tokenOwner;
    }

    function balanceOf(address account) public view returns (uint256) {
        require(account != address(0), "Zero address");
        return _balances[account];
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _approvals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _approvals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

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

        positions[tokenId].owner = to;

        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || getApproved(tokenId) == spender || isApprovedForAll(tokenOwner, spender));
    }
}

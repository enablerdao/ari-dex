// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PerpetualMarket
/// @author ARI DEX
/// @notice Simplified perpetual futures market with USDC collateral
contract PerpetualMarket {
    using SafeERC20 for IERC20;

    // ─── Constants ──────────────────────────────────────────────────────

    uint256 public constant MAX_LEVERAGE = 20;
    uint256 public constant LIQUIDATION_THRESHOLD = 500; // 5% in basis points
    uint256 public constant LIQUIDATION_PENALTY = 250;   // 2.5% in basis points
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant PRICE_DECIMALS = 1e6;        // 6 decimals for price
    uint256 public constant FUNDING_INTERVAL = 8 hours;
    uint256 public constant MAX_FUNDING_RATE = 100;       // 1% per 8h in basis points

    // ─── State ──────────────────────────────────────────────────────────

    address public owner;
    IERC20 public collateralToken; // USDC
    uint256 public currentPrice;   // 6 decimals

    uint256 public nextPositionId;
    uint256 public totalLongOI;    // open interest in base token units
    uint256 public totalShortOI;

    uint256 public insuranceFund;
    uint256 public lastFundingTime;

    mapping(uint256 => Position) public positions;

    // ─── Structs ────────────────────────────────────────────────────────

    struct Position {
        address trader;
        bool isLong;
        uint256 size;           // position size in base token units
        uint256 collateral;     // USDC collateral
        uint256 entryPrice;     // entry price (6 decimals)
        uint256 lastFundingTime;
        bool isOpen;
    }

    // ─── Events ─────────────────────────────────────────────────────────

    event PositionOpened(uint256 indexed positionId, address indexed trader, bool isLong, uint256 size, uint256 collateral, uint256 entryPrice);
    event PositionClosed(uint256 indexed positionId, address indexed trader, int256 pnl);
    event CollateralAdded(uint256 indexed positionId, uint256 amount);
    event PositionLiquidated(uint256 indexed positionId, address indexed liquidator, uint256 penalty);
    event PriceUpdated(uint256 newPrice);

    // ─── Errors ─────────────────────────────────────────────────────────

    error Unauthorized();
    error ExceedsMaxLeverage();
    error PositionNotOpen();
    error PositionHealthy();
    error InvalidSize();
    error InvalidCollateral();
    error InvalidPrice();
    error InsufficientBalance();

    // ─── Modifiers ──────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ─── Constructor ────────────────────────────────────────────────────

    constructor(address _collateralToken, uint256 _initialPrice) {
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
        currentPrice = _initialPrice;
        lastFundingTime = block.timestamp;
    }

    // ─── External Functions ─────────────────────────────────────────────

    function openPosition(
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 maxLeverage
    ) external returns (uint256 positionId) {
        if (size == 0) revert InvalidSize();
        if (collateral == 0) revert InvalidCollateral();
        if (maxLeverage > MAX_LEVERAGE) revert ExceedsMaxLeverage();

        uint256 notionalValue = (size * currentPrice) / PRICE_DECIMALS;
        if (notionalValue > collateral * maxLeverage) revert ExceedsMaxLeverage();

        collateralToken.safeTransferFrom(msg.sender, address(this), collateral);

        positionId = nextPositionId++;

        positions[positionId] = Position({
            trader: msg.sender,
            isLong: isLong,
            size: size,
            collateral: collateral,
            entryPrice: currentPrice,
            lastFundingTime: block.timestamp,
            isOpen: true
        });

        if (isLong) {
            totalLongOI += size;
        } else {
            totalShortOI += size;
        }

        emit PositionOpened(positionId, msg.sender, isLong, size, collateral, currentPrice);
    }

    function closePosition(uint256 positionId) external {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionNotOpen();
        if (pos.trader != msg.sender) revert Unauthorized();

        int256 pnl = calculatePnL(positionId, currentPrice);
        pos.isOpen = false;

        if (pos.isLong) {
            totalLongOI -= pos.size;
        } else {
            totalShortOI -= pos.size;
        }

        uint256 payout;
        if (pnl >= 0) {
            payout = pos.collateral + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            payout = loss >= pos.collateral ? 0 : pos.collateral - loss;
        }

        if (payout > 0) {
            collateralToken.safeTransfer(msg.sender, payout);
        }

        emit PositionClosed(positionId, msg.sender, pnl);
    }

    function addCollateral(uint256 positionId, uint256 amount) external {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionNotOpen();
        if (amount == 0) revert InvalidCollateral();

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        pos.collateral += amount;

        emit CollateralAdded(positionId, amount);
    }

    /// @notice Liquidate an undercollateralized position using stored currentPrice
    /// @param positionId The position to liquidate
    function liquidate(uint256 positionId) external {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionNotOpen();

        // Use stored currentPrice instead of caller-supplied price
        uint256 marginRatio = calculateMarginRatio(positionId, currentPrice);
        if (marginRatio >= LIQUIDATION_THRESHOLD) revert PositionHealthy();

        pos.isOpen = false;

        if (pos.isLong) {
            totalLongOI -= pos.size;
        } else {
            totalShortOI -= pos.size;
        }

        // Liquidation penalty goes to insurance fund
        uint256 penalty = (pos.collateral * LIQUIDATION_PENALTY) / BASIS_POINTS;
        insuranceFund += penalty;

        // Remaining collateral minus penalty goes to liquidator as reward
        uint256 remaining = pos.collateral > penalty ? pos.collateral - penalty : 0;
        uint256 liquidatorReward = remaining / 2;

        if (liquidatorReward > 0) {
            collateralToken.safeTransfer(msg.sender, liquidatorReward);
        }

        emit PositionLiquidated(positionId, msg.sender, penalty);
    }

    function setPrice(uint256 price) external onlyOwner {
        if (price == 0) revert InvalidPrice();
        currentPrice = price;
        emit PriceUpdated(price);
    }

    // ─── View Functions ─────────────────────────────────────────────────

    function calculatePnL(uint256 positionId, uint256 price) public view returns (int256 pnl) {
        Position storage pos = positions[positionId];

        if (pos.isLong) {
            pnl = int256((pos.size * price) / PRICE_DECIMALS) - int256((pos.size * pos.entryPrice) / PRICE_DECIMALS);
        } else {
            pnl = int256((pos.size * pos.entryPrice) / PRICE_DECIMALS) - int256((pos.size * price) / PRICE_DECIMALS);
        }
    }

    function calculateMarginRatio(uint256 positionId, uint256 price) public view returns (uint256 ratio) {
        Position storage pos = positions[positionId];

        int256 pnl = calculatePnL(positionId, price);
        int256 equity = int256(pos.collateral) + pnl;

        if (equity <= 0) return 0;

        uint256 notionalValue = (pos.size * price) / PRICE_DECIMALS;
        if (notionalValue == 0) return 0;

        ratio = (uint256(equity) * BASIS_POINTS) / notionalValue;
    }

    function getPositionCore(uint256 positionId) external view returns (address trader, bool isLong, uint256 size, uint256 collateral) {
        Position storage pos = positions[positionId];
        return (pos.trader, pos.isLong, pos.size, pos.collateral);
    }

    function getPositionMeta(uint256 positionId) external view returns (uint256 entryPrice, uint256 fundingTime, bool isOpen) {
        Position storage pos = positions[positionId];
        return (pos.entryPrice, pos.lastFundingTime, pos.isOpen);
    }

    function getFundingRate() external view returns (int256 rate) {
        uint256 totalOI = totalLongOI + totalShortOI;
        if (totalOI == 0) return 0;

        int256 imbalance = int256(totalLongOI) - int256(totalShortOI);
        rate = (imbalance * int256(MAX_FUNDING_RATE)) / int256(totalOI);
    }
}

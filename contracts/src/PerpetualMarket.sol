// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title PerpetualMarket
/// @author ARI DEX
/// @notice Simplified perpetual futures market with USDC collateral
contract PerpetualMarket {
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

    /// @notice Open a new perpetual position
    /// @param isLong True for long, false for short
    /// @param size Position size in base token units
    /// @param collateral USDC collateral amount
    /// @param maxLeverage Maximum acceptable leverage (must be <= MAX_LEVERAGE)
    function openPosition(
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 maxLeverage
    ) external returns (uint256 positionId) {
        if (size == 0) revert InvalidSize();
        if (collateral == 0) revert InvalidCollateral();
        if (maxLeverage > MAX_LEVERAGE) revert ExceedsMaxLeverage();

        // Calculate notional value: size * currentPrice / PRICE_DECIMALS
        uint256 notionalValue = (size * currentPrice) / PRICE_DECIMALS;

        // Check leverage: notional / collateral <= maxLeverage
        if (notionalValue > collateral * maxLeverage) revert ExceedsMaxLeverage();

        // Transfer collateral from trader
        collateralToken.transferFrom(msg.sender, address(this), collateral);

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

    /// @notice Close an open position and settle PnL
    /// @param positionId The position to close
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

        // Settlement: return collateral +/- PnL
        uint256 payout;
        if (pnl >= 0) {
            payout = pos.collateral + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            payout = loss >= pos.collateral ? 0 : pos.collateral - loss;
        }

        if (payout > 0) {
            collateralToken.transfer(msg.sender, payout);
        }

        emit PositionClosed(positionId, msg.sender, pnl);
    }

    /// @notice Add collateral to an existing position
    /// @param positionId The position to add collateral to
    /// @param amount Amount of USDC to add
    function addCollateral(uint256 positionId, uint256 amount) external {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionNotOpen();
        if (amount == 0) revert InvalidCollateral();

        collateralToken.transferFrom(msg.sender, address(this), amount);
        pos.collateral += amount;

        emit CollateralAdded(positionId, amount);
    }

    /// @notice Liquidate an undercollateralized position
    /// @param positionId The position to liquidate
    /// @param price Current price to evaluate margin ratio at
    function liquidate(uint256 positionId, uint256 price) external {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionNotOpen();

        uint256 marginRatio = calculateMarginRatio(positionId, price);
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
        // The other half stays in the contract (covers counterparty PnL)

        if (liquidatorReward > 0) {
            collateralToken.transfer(msg.sender, liquidatorReward);
        }

        emit PositionLiquidated(positionId, msg.sender, penalty);
    }

    /// @notice Owner sets the oracle price (simplified)
    /// @param price New price with 6 decimals
    function setPrice(uint256 price) external onlyOwner {
        if (price == 0) revert InvalidPrice();
        currentPrice = price;
        emit PriceUpdated(price);
    }

    // ─── View Functions ─────────────────────────────────────────────────

    /// @notice Calculate unrealized PnL for a position at a given price
    /// @param positionId Position to evaluate
    /// @param price Price to evaluate at (6 decimals)
    /// @return pnl Signed PnL in collateral token units
    function calculatePnL(uint256 positionId, uint256 price) public view returns (int256 pnl) {
        Position storage pos = positions[positionId];

        if (pos.isLong) {
            // Long: profit when price goes up
            // PnL = size * (price - entryPrice) / PRICE_DECIMALS
            pnl = int256((pos.size * price) / PRICE_DECIMALS) - int256((pos.size * pos.entryPrice) / PRICE_DECIMALS);
        } else {
            // Short: profit when price goes down
            // PnL = size * (entryPrice - price) / PRICE_DECIMALS
            pnl = int256((pos.size * pos.entryPrice) / PRICE_DECIMALS) - int256((pos.size * price) / PRICE_DECIMALS);
        }
    }

    /// @notice Calculate margin ratio for a position at a given price
    /// @param positionId Position to evaluate
    /// @param price Price to evaluate at (6 decimals)
    /// @return ratio Margin ratio in basis points (10000 = 100%)
    function calculateMarginRatio(uint256 positionId, uint256 price) public view returns (uint256 ratio) {
        Position storage pos = positions[positionId];

        int256 pnl = calculatePnL(positionId, price);
        int256 equity = int256(pos.collateral) + pnl;

        if (equity <= 0) return 0;

        uint256 notionalValue = (pos.size * price) / PRICE_DECIMALS;
        if (notionalValue == 0) return 0;

        ratio = (uint256(equity) * BASIS_POINTS) / notionalValue;
    }

    /// @notice Get position details split into two calls to avoid stack-too-deep
    function getPositionCore(uint256 positionId) external view returns (address trader, bool isLong, uint256 size, uint256 collateral) {
        Position storage pos = positions[positionId];
        return (pos.trader, pos.isLong, pos.size, pos.collateral);
    }

    function getPositionMeta(uint256 positionId) external view returns (uint256 entryPrice, uint256 fundingTime, bool isOpen) {
        Position storage pos = positions[positionId];
        return (pos.entryPrice, pos.lastFundingTime, pos.isOpen);
    }

    /// @notice Get the current funding rate based on long/short OI imbalance
    /// @return rate Signed funding rate in basis points (positive = longs pay shorts)
    function getFundingRate() external view returns (int256 rate) {
        uint256 totalOI = totalLongOI + totalShortOI;
        if (totalOI == 0) return 0;

        // Funding rate = (longOI - shortOI) / totalOI * MAX_FUNDING_RATE
        // Positive = longs pay shorts, negative = shorts pay longs
        int256 imbalance = int256(totalLongOI) - int256(totalShortOI);
        rate = (imbalance * int256(MAX_FUNDING_RATE)) / int256(totalOI);
    }
}

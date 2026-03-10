//! Order types for the hybrid order book.

use serde::{Deserialize, Serialize};

use crate::token::TokenPair;

/// Buy or sell side of an order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OrderSide {
    /// Buying the base token.
    Buy,
    /// Selling the base token.
    Sell,
}

/// A limit order placed at a specific price.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LimitOrder {
    /// Unique order identifier.
    pub id: u64,
    /// Trader's address.
    pub owner: [u8; 20],
    /// Token pair for this order.
    pub pair: TokenPair,
    /// Buy or sell.
    pub side: OrderSide,
    /// Limit price as a Q64.96 fixed-point value.
    pub price: u128,
    /// Order quantity (U256, big-endian).
    pub quantity: [u8; 32],
    /// Remaining unfilled quantity (U256, big-endian).
    pub remaining: [u8; 32],
    /// Unix timestamp of order placement.
    pub timestamp: u64,
}

/// A market order that executes at the best available price.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketOrder {
    /// Unique order identifier.
    pub id: u64,
    /// Trader's address.
    pub owner: [u8; 20],
    /// Token pair for this order.
    pub pair: TokenPair,
    /// Buy or sell.
    pub side: OrderSide,
    /// Order quantity (U256, big-endian).
    pub quantity: [u8; 32],
    /// Maximum acceptable slippage in basis points.
    pub max_slippage_bps: u32,
}

//! Market depth (level 2) data.

use serde::{Deserialize, Serialize};

/// A single price level in the order book.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriceLevel {
    /// Price at this level (Q64.96).
    pub price: u128,
    /// Total quantity at this level.
    pub quantity: u128,
    /// Number of orders at this level.
    pub order_count: u32,
}

/// Aggregated market depth snapshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketDepth {
    /// Bid levels, sorted by price descending.
    pub bids: Vec<PriceLevel>,
    /// Ask levels, sorted by price ascending.
    pub asks: Vec<PriceLevel>,
}

impl MarketDepth {
    /// Returns the mid-market price, if both sides have liquidity.
    pub fn mid_price(&self) -> Option<u128> {
        match (self.bids.first(), self.asks.first()) {
            (Some(bid), Some(ask)) => Some((bid.price + ask.price) / 2),
            _ => None,
        }
    }

    /// Returns the bid-ask spread in price units.
    pub fn spread(&self) -> Option<u128> {
        match (self.bids.first(), self.asks.first()) {
            (Some(bid), Some(ask)) if ask.price > bid.price => {
                Some(ask.price - bid.price)
            }
            _ => None,
        }
    }
}

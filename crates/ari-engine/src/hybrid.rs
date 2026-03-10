//! Hybrid router that selects the optimal execution venue.

use ari_core::{Intent, TokenPair};

/// Execution venue recommendation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Venue {
    /// Route through concentrated liquidity pools.
    Clmm,
    /// Route through the order book.
    OrderBook,
    /// Include in the next batch auction.
    BatchAuction,
}

/// Routes intents to the optimal execution venue based on
/// liquidity depth, order size, and market conditions.
#[derive(Debug, Clone)]
pub struct HybridRouter {
    /// Minimum order size (in USD equivalent) to consider batch auction.
    pub batch_threshold: u128,
}

impl HybridRouter {
    /// Creates a new hybrid router with default thresholds.
    pub fn new() -> Self {
        Self {
            batch_threshold: 10_000,
        }
    }

    /// Determines the best execution venue for a given intent.
    pub fn route(&self, _intent: &Intent) -> Venue {
        // TODO: Implement smart routing logic based on:
        // - Available CLMM liquidity depth
        // - Order book spread
        // - Intent size relative to available liquidity
        // - Cross-chain requirements
        Venue::Clmm
    }

    /// Determines the best venue for a given token pair and amount.
    pub fn route_for_pair(&self, _pair: &TokenPair, _amount: u128) -> Venue {
        // TODO: Compare liquidity across venues
        Venue::Clmm
    }
}

impl Default for HybridRouter {
    fn default() -> Self {
        Self::new()
    }
}

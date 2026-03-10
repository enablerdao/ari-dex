//! Global engine state.

use std::collections::HashMap;

use ari_core::TokenPair;

use crate::batch::BatchAuction;
use crate::clmm::ConcentratedPool;
use crate::orderbook::OrderBook;

/// Central state of the ARI matching engine.
///
/// Holds all pools, order books, and the active batch auction.
#[derive(Debug)]
pub struct EngineState {
    /// CLMM pools indexed by pool address.
    pub pools: HashMap<[u8; 20], ConcentratedPool>,
    /// Order books indexed by token pair.
    pub order_books: HashMap<TokenPair, OrderBook>,
    /// Currently active batch auction, if any.
    pub active_batch: Option<BatchAuction>,
}

impl EngineState {
    /// Creates a new empty engine state.
    pub fn new() -> Self {
        Self {
            pools: HashMap::new(),
            order_books: HashMap::new(),
            active_batch: None,
        }
    }
}

impl Default for EngineState {
    fn default() -> Self {
        Self::new()
    }
}

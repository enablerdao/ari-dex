//! ARI DEX matching engine.
//!
//! Provides three execution modes:
//! - **CLMM**: Concentrated Liquidity Market Maker pools
//! - **OrderBook**: Traditional limit order book
//! - **Batch**: Periodic batch auctions with uniform clearing price
//!
//! The [`HybridRouter`](hybrid::HybridRouter) intelligently routes trades
//! to the optimal execution venue.

pub mod batch;
pub mod clmm;
pub mod hybrid;
pub mod orderbook;
pub mod state;

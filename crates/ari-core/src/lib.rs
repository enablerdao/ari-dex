//! ARI DEX core types and data structures.
//!
//! This crate defines the fundamental types used across the ARI decentralized exchange,
//! including intents, tokens, chains, solutions, pools, orders, batches, and errors.

pub mod batch;
pub mod chain;
pub mod error;
pub mod intent;
pub mod order;
pub mod pool;
pub mod solution;
pub mod token;

pub use batch::{Batch, BatchResult, BatchStatus};
pub use chain::{ChainConfig, ChainId};
pub use error::AriError;
pub use intent::{Intent, IntentId, IntentStatus};
pub use order::{LimitOrder, MarketOrder, OrderSide};
pub use pool::{FeeTier, Pool, Position, Tick};
pub use solution::{Hop, Solution};
pub use token::{Token, TokenPair};

/// Convenience type alias for results throughout the ARI codebase.
pub type Result<T> = std::result::Result<T, AriError>;

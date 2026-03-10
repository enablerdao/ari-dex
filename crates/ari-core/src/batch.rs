//! Batch auction types.

use serde::{Deserialize, Serialize};

use crate::intent::IntentId;
use crate::solution::Solution;

/// Lifecycle status of a batch auction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BatchStatus {
    /// Accepting new intents.
    Open,
    /// Closed for new intents; solvers computing solutions.
    Closed,
    /// Solutions evaluated; clearing price determined.
    Solved,
    /// Batch results settled on-chain.
    Settled,
}

/// A batch of intents grouped for simultaneous execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Batch {
    /// Monotonically increasing batch identifier.
    pub id: u64,
    /// Intent IDs included in this batch.
    pub intents: Vec<IntentId>,
    /// Unix timestamp when the batch opened.
    pub start_time: u64,
    /// Unix timestamp when the batch closes.
    pub end_time: u64,
    /// Current status of the batch.
    pub status: BatchStatus,
}

/// Result of a completed batch auction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchResult {
    /// The batch this result belongs to.
    pub batch_id: u64,
    /// Winning solutions for each intent.
    pub solutions: Vec<Solution>,
    /// Uniform clearing price (Q64.96 fixed-point).
    pub clearing_price: u128,
    /// Total volume traded in this batch (U256, big-endian).
    pub total_volume: [u8; 32],
}

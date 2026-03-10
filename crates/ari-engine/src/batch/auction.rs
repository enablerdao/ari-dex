//! Batch auction implementation.

use ari_core::{Batch, BatchResult, BatchStatus, Intent, IntentId};

/// Manages a batch auction cycle: collect intents, close, solve, settle.
#[derive(Debug)]
pub struct BatchAuction {
    /// Current batch.
    current_batch: Batch,
    /// Intents collected for the current batch.
    intents: Vec<Intent>,
}

impl BatchAuction {
    /// Creates a new batch auction with the given batch ID and time window.
    pub fn new(batch_id: u64, start_time: u64, end_time: u64) -> Self {
        Self {
            current_batch: Batch {
                id: batch_id,
                intents: Vec::new(),
                start_time,
                end_time,
                status: BatchStatus::Open,
            },
            intents: Vec::new(),
        }
    }

    /// Submits an intent to the current batch.
    ///
    /// Returns the intent ID on success, or an error if the batch is closed.
    pub fn submit_intent(&mut self, intent: Intent) -> ari_core::Result<IntentId> {
        if self.current_batch.status != BatchStatus::Open {
            return Err(ari_core::AriError::BatchClosed);
        }

        // Derive intent ID from nonce (simplified; real impl would hash all fields)
        let mut id = [0u8; 32];
        id[24..32].copy_from_slice(&intent.nonce.to_be_bytes());
        let intent_id = IntentId(id);

        self.current_batch.intents.push(intent_id);
        self.intents.push(intent);

        Ok(intent_id)
    }

    /// Closes the current batch, preventing new intent submissions.
    pub fn close_batch(&mut self) {
        self.current_batch.status = BatchStatus::Closed;
    }

    /// Computes the clearing price and produces a batch result.
    ///
    /// Must be called after `close_batch()`.
    pub fn compute_clearing_price(&mut self) -> ari_core::Result<BatchResult> {
        if self.current_batch.status != BatchStatus::Closed {
            return Err(ari_core::AriError::InternalError(
                "batch must be closed before computing clearing price".into(),
            ));
        }

        self.current_batch.status = BatchStatus::Solved;

        // TODO: Implement real clearing price algorithm
        Ok(BatchResult {
            batch_id: self.current_batch.id,
            solutions: Vec::new(),
            clearing_price: 0,
            total_volume: [0u8; 32],
        })
    }

    /// Returns a reference to the current batch.
    pub fn current_batch(&self) -> &Batch {
        &self.current_batch
    }
}

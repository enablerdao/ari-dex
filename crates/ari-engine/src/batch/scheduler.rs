//! Batch scheduling and timing.

/// Default batch interval in seconds.
pub const DEFAULT_BATCH_INTERVAL_SECS: u64 = 5;

/// Determines when the next batch should open and close.
#[derive(Debug, Clone)]
pub struct BatchScheduler {
    /// Interval between batches in seconds.
    interval_secs: u64,
    /// ID of the next batch.
    next_batch_id: u64,
}

impl BatchScheduler {
    /// Creates a new scheduler with the given interval.
    pub fn new(interval_secs: u64) -> Self {
        Self {
            interval_secs,
            next_batch_id: 1,
        }
    }

    /// Returns the next batch ID and advances the counter.
    pub fn next_batch_id(&mut self) -> u64 {
        let id = self.next_batch_id;
        self.next_batch_id += 1;
        id
    }

    /// Returns the batch interval in seconds.
    pub fn interval_secs(&self) -> u64 {
        self.interval_secs
    }
}

impl Default for BatchScheduler {
    fn default() -> Self {
        Self::new(DEFAULT_BATCH_INTERVAL_SECS)
    }
}

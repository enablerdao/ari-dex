//! Batch scheduling and timing.
//!
//! Manages epoch-based batch auction scheduling with configurable
//! duration. Default epoch is 250ms for low-latency execution.

use std::time::{Duration, Instant};

/// Default batch epoch duration.
pub const DEFAULT_EPOCH_DURATION: Duration = Duration::from_millis(250);

/// Default batch interval in seconds (kept for backward compatibility).
pub const DEFAULT_BATCH_INTERVAL_SECS: u64 = 5;

/// Epoch state: tracks whether we're in a collection or solving phase.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpochPhase {
    /// Accepting new intents.
    Collecting,
    /// Batch is closed; solver is computing.
    Solving,
    /// Solution found; settling on-chain.
    Settling,
}

/// Determines when the next batch should open and close.
///
/// The scheduler runs on a fixed epoch cycle:
///   1. **Collecting** (configurable duration, default 250ms): accept intents
///   2. **Solving** (variable): compute clearing price
///   3. **Settling** (variable): submit on-chain
///
/// After settling, the next collection epoch starts immediately.
#[derive(Debug, Clone)]
pub struct BatchScheduler {
    /// Duration of the collection phase.
    epoch_duration: Duration,
    /// ID of the next batch.
    next_batch_id: u64,
    /// Current phase.
    phase: EpochPhase,
    /// When the current phase started.
    phase_start: Instant,
    /// Total batches completed.
    completed_batches: u64,
}

impl BatchScheduler {
    /// Creates a new scheduler with the given epoch duration.
    pub fn with_epoch_duration(epoch_duration: Duration) -> Self {
        Self {
            epoch_duration,
            next_batch_id: 1,
            phase: EpochPhase::Collecting,
            phase_start: Instant::now(),
            completed_batches: 0,
        }
    }

    /// Creates a new scheduler with the given interval in seconds.
    pub fn new(interval_secs: u64) -> Self {
        Self::with_epoch_duration(Duration::from_secs(interval_secs))
    }

    /// Returns the next batch ID and advances the counter.
    pub fn next_batch_id(&mut self) -> u64 {
        let id = self.next_batch_id;
        self.next_batch_id += 1;
        id
    }

    /// Returns the batch interval in seconds.
    pub fn interval_secs(&self) -> u64 {
        self.epoch_duration.as_secs()
    }

    /// Returns the epoch duration.
    pub fn epoch_duration(&self) -> Duration {
        self.epoch_duration
    }

    /// Returns the current epoch phase.
    pub fn phase(&self) -> EpochPhase {
        self.phase
    }

    /// Checks if the current collection epoch has expired.
    pub fn collection_expired(&self) -> bool {
        self.phase == EpochPhase::Collecting
            && self.phase_start.elapsed() >= self.epoch_duration
    }

    /// Transitions to the solving phase.
    ///
    /// Returns the (start_time, end_time) as unix timestamps for the batch.
    pub fn start_solving(&mut self) -> (u64, u64) {
        let start_ts = self
            .phase_start
            .elapsed()
            .as_secs();
        self.phase = EpochPhase::Solving;
        self.phase_start = Instant::now();
        (start_ts, start_ts + self.epoch_duration.as_secs())
    }

    /// Transitions to the settling phase.
    pub fn start_settling(&mut self) {
        self.phase = EpochPhase::Settling;
        self.phase_start = Instant::now();
    }

    /// Completes the current batch and starts a new collection epoch.
    pub fn complete_batch(&mut self) {
        self.completed_batches += 1;
        self.phase = EpochPhase::Collecting;
        self.phase_start = Instant::now();
    }

    /// Returns the number of completed batches.
    pub fn completed_batches(&self) -> u64 {
        self.completed_batches
    }

    /// Creates batch time window (start, end) in unix seconds for a new batch.
    pub fn next_batch_window(&self, current_time_secs: u64) -> (u64, u64) {
        let end = current_time_secs + self.epoch_duration.as_secs().max(1);
        (current_time_secs, end)
    }
}

impl Default for BatchScheduler {
    fn default() -> Self {
        Self::with_epoch_duration(DEFAULT_EPOCH_DURATION)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_epoch_250ms() {
        let s = BatchScheduler::default();
        assert_eq!(s.epoch_duration(), Duration::from_millis(250));
    }

    #[test]
    fn phase_transitions() {
        let mut s = BatchScheduler::with_epoch_duration(Duration::from_millis(1));
        assert_eq!(s.phase(), EpochPhase::Collecting);

        s.start_solving();
        assert_eq!(s.phase(), EpochPhase::Solving);

        s.start_settling();
        assert_eq!(s.phase(), EpochPhase::Settling);

        s.complete_batch();
        assert_eq!(s.phase(), EpochPhase::Collecting);
        assert_eq!(s.completed_batches(), 1);
    }

    #[test]
    fn batch_id_increments() {
        let mut s = BatchScheduler::default();
        assert_eq!(s.next_batch_id(), 1);
        assert_eq!(s.next_batch_id(), 2);
        assert_eq!(s.next_batch_id(), 3);
    }

    #[test]
    fn batch_window() {
        let s = BatchScheduler::new(5);
        let (start, end) = s.next_batch_window(1000);
        assert_eq!(start, 1000);
        assert_eq!(end, 1005);
    }
}

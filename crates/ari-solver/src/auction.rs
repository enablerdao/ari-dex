//! Dutch auction mechanism for solver competition.

use serde::{Deserialize, Serialize};

/// A Dutch auction where the price decreases over time until a solver accepts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DutchAuction {
    /// Starting price (highest, most favorable for the user).
    pub start_price: u128,
    /// Ending price (lowest acceptable).
    pub end_price: u128,
    /// Auction start timestamp.
    pub start_time: u64,
    /// Auction end timestamp.
    pub end_time: u64,
}

impl DutchAuction {
    /// Creates a new Dutch auction.
    pub fn new(start_price: u128, end_price: u128, start_time: u64, end_time: u64) -> Self {
        Self {
            start_price,
            end_price,
            start_time,
            end_time,
        }
    }

    /// Returns the current price at the given timestamp.
    ///
    /// Price decreases linearly from `start_price` to `end_price`
    /// over the auction duration.
    pub fn current_price(&self, now: u64) -> u128 {
        if now <= self.start_time {
            return self.start_price;
        }
        if now >= self.end_time {
            return self.end_price;
        }

        let elapsed = now - self.start_time;
        let duration = self.end_time - self.start_time;
        let price_diff = self.start_price - self.end_price;

        self.start_price - (price_diff * elapsed as u128) / duration as u128
    }

    /// Returns true if the auction has ended.
    pub fn is_expired(&self, now: u64) -> bool {
        now >= self.end_time
    }
}

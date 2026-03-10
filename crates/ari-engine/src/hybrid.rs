//! Hybrid router that selects the optimal execution venue.
//!
//! Routes trades to CLMM pools, order books, or batch auctions based on
//! liquidity depth, order size, and spread analysis.

use ari_core::{Intent, TokenPair};

use crate::clmm::ConcentratedPool;
use crate::orderbook::OrderBook;

/// Execution venue recommendation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Venue {
    /// Route through concentrated liquidity pools.
    Clmm,
    /// Route through the order book.
    OrderBook,
    /// Include in the next batch auction.
    BatchAuction,
    /// Split across multiple venues.
    Split {
        /// Fraction (0-100) to route through CLMM.
        clmm_pct: u8,
        /// Fraction (0-100) to route through order book.
        ob_pct: u8,
    },
}

/// Liquidity snapshot used for routing decisions.
#[derive(Debug, Clone, Copy, Default)]
pub struct LiquidityInfo {
    /// Estimated CLMM output for the requested amount.
    pub clmm_output: u128,
    /// Whether a CLMM pool exists for this pair.
    pub clmm_available: bool,
    /// Order book best bid.
    pub ob_best_bid: Option<u128>,
    /// Order book best ask.
    pub ob_best_ask: Option<u128>,
    /// Whether the order book has liquidity for this pair.
    pub ob_available: bool,
    /// Order book spread in basis points.
    pub ob_spread_bps: u32,
}

/// Routes intents to the optimal execution venue based on
/// liquidity depth, order size, and market conditions.
#[derive(Debug, Clone)]
pub struct HybridRouter {
    /// Minimum order size (in token units) to consider batch auction.
    /// Large orders benefit from MEV protection in batch auctions.
    pub batch_threshold: u128,
    /// Maximum acceptable spread (bps) to route through order book.
    /// If spread exceeds this, prefer CLMM.
    pub max_ob_spread_bps: u32,
    /// Minimum improvement (bps) to justify splitting across venues.
    pub split_benefit_threshold_bps: u32,
}

impl HybridRouter {
    /// Creates a new hybrid router with default thresholds.
    pub fn new() -> Self {
        Self {
            batch_threshold: 10_000_000_000_000_000_000, // 10 token units (18 decimals)
            max_ob_spread_bps: 50, // 0.5%
            split_benefit_threshold_bps: 10, // 0.1% improvement needed to justify split
        }
    }

    /// Determines the best execution venue for a given intent.
    pub fn route(&self, intent: &Intent) -> Venue {
        let amount = u128_from_be_bytes(&intent.sell_amount);

        // Large orders go to batch auction for MEV protection
        if amount >= self.batch_threshold {
            return Venue::BatchAuction;
        }

        // Default to CLMM for standard swaps
        Venue::Clmm
    }

    /// Determines the best venue for a given token pair and amount,
    /// using live liquidity information from both venues.
    pub fn route_with_liquidity(
        &self,
        _pair: &TokenPair,
        amount: u128,
        pool: Option<&ConcentratedPool>,
        orderbook: Option<&OrderBook>,
    ) -> Venue {
        // Large orders: batch auction
        if amount >= self.batch_threshold {
            return Venue::BatchAuction;
        }

        let clmm_available = pool.map_or(false, |p| p.liquidity() > 0);
        let ob_available = orderbook.map_or(false, |ob| {
            ob.best_bid().is_some() && ob.best_ask().is_some()
        });

        match (clmm_available, ob_available) {
            (false, false) => {
                // No liquidity anywhere — batch auction as last resort
                Venue::BatchAuction
            }
            (true, false) => Venue::Clmm,
            (false, true) => Venue::OrderBook,
            (true, true) => {
                // Both available: check order book spread
                let ob = orderbook.unwrap();
                let spread = compute_spread_bps(ob);

                if spread > self.max_ob_spread_bps {
                    // Wide spread: CLMM is likely better
                    Venue::Clmm
                } else {
                    // Tight spread: compare price impact
                    // For simplicity, use order book when spread is tight
                    // A production system would simulate both paths
                    self.evaluate_split(amount, pool.unwrap(), ob)
                }
            }
        }
    }

    /// Determines the best venue for a given token pair and amount.
    /// Simplified version without live liquidity data.
    pub fn route_for_pair(&self, _pair: &TokenPair, amount: u128) -> Venue {
        if amount >= self.batch_threshold {
            Venue::BatchAuction
        } else {
            Venue::Clmm
        }
    }

    /// Evaluates whether splitting across CLMM and order book is beneficial.
    fn evaluate_split(
        &self,
        amount: u128,
        pool: &ConcentratedPool,
        ob: &OrderBook,
    ) -> Venue {
        // Simple heuristic: if pool liquidity is less than 2x the order amount,
        // split to reduce price impact.
        let pool_liq = pool.liquidity();

        if pool_liq < amount * 2 {
            // CLMM doesn't have deep enough liquidity for full fill.
            // Check if OB can absorb some.
            let ob_has_depth = ob.best_bid().is_some() && ob.best_ask().is_some();
            if ob_has_depth {
                // Split: 60% CLMM, 40% OB (heuristic)
                Venue::Split {
                    clmm_pct: 60,
                    ob_pct: 40,
                }
            } else {
                Venue::Clmm
            }
        } else {
            // Enough CLMM liquidity for the full amount
            Venue::Clmm
        }
    }
}

impl Default for HybridRouter {
    fn default() -> Self {
        Self::new()
    }
}

/// Computes the spread of the order book in basis points.
fn compute_spread_bps(ob: &OrderBook) -> u32 {
    match (ob.best_bid(), ob.best_ask()) {
        (Some(bid), Some(ask)) if bid > 0 => {
            if ask <= bid {
                return 0; // Crossed book
            }
            let spread = ask - bid;
            // spread_bps = (spread / mid) * 10_000
            let mid = (ask + bid) / 2;
            if mid == 0 {
                return u32::MAX;
            }
            ((spread as f64 / mid as f64) * 10_000.0) as u32
        }
        _ => u32::MAX, // No two-sided market
    }
}

/// Extracts a u128 from the lower 16 bytes of a big-endian [u8; 32].
fn u128_from_be_bytes(bytes: &[u8; 32]) -> u128 {
    let mut buf = [0u8; 16];
    buf.copy_from_slice(&bytes[16..32]);
    u128::from_be_bytes(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::{ChainId, Token};

    fn make_token(symbol: &str) -> Token {
        Token {
            chain: ChainId::Ethereum,
            address: [0u8; 20],
            symbol: symbol.to_string(),
            decimals: 18,
        }
    }

    fn make_intent(sell_amount: u128) -> Intent {
        let mut sell_bytes = [0u8; 32];
        sell_bytes[16..32].copy_from_slice(&sell_amount.to_be_bytes());
        Intent {
            sender: [0u8; 20],
            sell_token: make_token("A"),
            buy_token: make_token("B"),
            sell_amount: sell_bytes,
            buy_amount: [0u8; 32],
            min_buy: [0u8; 32],
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 0,
            signature: [0u8; 65],
        }
    }

    #[test]
    fn small_order_goes_to_clmm() {
        let router = HybridRouter::new();
        let intent = make_intent(1000);
        assert_eq!(router.route(&intent), Venue::Clmm);
    }

    #[test]
    fn large_order_goes_to_batch() {
        let router = HybridRouter::new();
        let intent = make_intent(100_000_000_000_000_000_000); // 100 tokens
        assert_eq!(router.route(&intent), Venue::BatchAuction);
    }
}

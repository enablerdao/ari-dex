//! Dutch auction mechanism for solver competition.
//!
//! Solvers submit solutions during a configurable auction window.
//! The auction finalises by selecting the solution with the best score
//! (highest output, lowest gas).

use std::time::{Duration, Instant};

use ari_core::{Intent, Solution};

/// Default auction duration in milliseconds.
const DEFAULT_DURATION_MS: u64 = 200;

/// A submitted solution with solver metadata.
#[derive(Debug, Clone)]
pub struct SolverSubmission {
    /// Unique identifier for the solver.
    pub solver_id: [u8; 20],
    /// The proposed solution.
    pub solution: Solution,
    /// Timestamp when the submission was received.
    pub submitted_at: Instant,
}

/// The winning solution after auction finalisation.
#[derive(Debug, Clone)]
pub struct WinningSolution {
    /// The solver that won.
    pub solver_id: [u8; 20],
    /// The winning solution.
    pub solution: Solution,
    /// Score of the winning solution.
    pub score: f64,
}

/// Status of the auction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuctionStatus {
    /// Accepting submissions.
    Open,
    /// Auction window has closed, awaiting finalisation.
    Closed,
    /// Winner has been selected.
    Finalised,
}

/// A Dutch auction where solvers compete to provide the best execution for an intent.
#[derive(Debug)]
pub struct DutchAuction {
    /// The intent being auctioned.
    pub intent: Intent,
    /// Starting price (highest, most favourable for the user).
    pub start_price: u128,
    /// Ending price (lowest acceptable).
    pub end_price: u128,
    /// Auction start instant.
    start_instant: Instant,
    /// Auction duration.
    duration: Duration,
    /// Submitted solutions.
    submissions: Vec<SolverSubmission>,
    /// Current status.
    status: AuctionStatus,
}

impl DutchAuction {
    /// Creates a new Dutch auction for the given intent.
    ///
    /// `duration_ms` controls how long the auction window stays open.
    /// If `None`, uses the default of 200ms.
    pub fn new(intent: Intent, duration_ms: Option<u64>) -> Self {
        let sell_amount = u128::from_be_bytes(
            intent.sell_amount[16..32]
                .try_into()
                .unwrap_or([0u8; 16]),
        );
        let min_buy = u128::from_be_bytes(
            intent.min_buy[16..32]
                .try_into()
                .unwrap_or([0u8; 16]),
        );

        Self {
            intent,
            start_price: sell_amount,
            end_price: min_buy,
            start_instant: Instant::now(),
            duration: Duration::from_millis(duration_ms.unwrap_or(DEFAULT_DURATION_MS)),
            submissions: Vec::new(),
            status: AuctionStatus::Open,
        }
    }

    /// Returns the current auction status.
    pub fn status(&self) -> AuctionStatus {
        if self.status == AuctionStatus::Finalised {
            return AuctionStatus::Finalised;
        }
        if self.start_instant.elapsed() >= self.duration {
            AuctionStatus::Closed
        } else {
            AuctionStatus::Open
        }
    }

    /// Returns the current price at the given elapsed fraction.
    pub fn current_price(&self) -> u128 {
        let elapsed = self.start_instant.elapsed();
        if elapsed >= self.duration {
            return self.end_price;
        }
        let elapsed_ms = elapsed.as_millis() as u128;
        let duration_ms = self.duration.as_millis() as u128;
        if duration_ms == 0 {
            return self.end_price;
        }
        let price_diff = self.start_price.saturating_sub(self.end_price);
        self.start_price - (price_diff * elapsed_ms) / duration_ms
    }

    /// Submit a solver's proposed solution.
    ///
    /// Returns `Err` if the auction is already closed or finalised.
    pub fn submit_solution(
        &mut self,
        solver_id: [u8; 20],
        solution: Solution,
    ) -> Result<(), &'static str> {
        match self.status() {
            AuctionStatus::Finalised => return Err("auction already finalised"),
            AuctionStatus::Closed => return Err("auction closed"),
            AuctionStatus::Open => {}
        }

        self.submissions.push(SolverSubmission {
            solver_id,
            solution,
            submitted_at: Instant::now(),
        });
        Ok(())
    }

    /// Finalise the auction and select the winning solution.
    ///
    /// The winner is the solution with the highest output amount; ties are
    /// broken by lowest gas cost.
    pub fn finalize(&mut self) -> Option<WinningSolution> {
        self.status = AuctionStatus::Finalised;

        if self.submissions.is_empty() {
            return None;
        }

        let winner = self
            .submissions
            .iter()
            .max_by(|a, b| {
                let out_a = u128::from_be_bytes(
                    a.solution.buy_amount[16..32].try_into().unwrap_or([0u8; 16]),
                );
                let out_b = u128::from_be_bytes(
                    b.solution.buy_amount[16..32].try_into().unwrap_or([0u8; 16]),
                );
                out_a
                    .cmp(&out_b)
                    .then(b.solution.gas_cost.cmp(&a.solution.gas_cost))
            })
            .unwrap();

        let output = u128::from_be_bytes(
            winner.solution.buy_amount[16..32]
                .try_into()
                .unwrap_or([0u8; 16]),
        ) as f64;
        let gas_penalty = winner.solution.gas_cost as f64 * 0.001;
        let score = output - gas_penalty;

        Some(WinningSolution {
            solver_id: winner.solver_id,
            solution: winner.solution.clone(),
            score,
        })
    }

    /// Returns the number of submissions received.
    pub fn submission_count(&self) -> usize {
        self.submissions.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::*;

    fn make_intent() -> Intent {
        let token = Token {
            chain: ChainId::Ethereum,
            address: [0u8; 20],
            symbol: "WETH".into(),
            decimals: 18,
        };
        let mut sell_amount = [0u8; 32];
        sell_amount[16..32].copy_from_slice(&1000u128.to_be_bytes());
        let mut min_buy = [0u8; 32];
        min_buy[16..32].copy_from_slice(&900u128.to_be_bytes());
        Intent {
            sender: [1u8; 20],
            sell_token: token.clone(),
            buy_token: Token {
                symbol: "USDC".into(),
                address: [2u8; 20],
                ..token
            },
            sell_amount,
            buy_amount: sell_amount,
            min_buy,
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 0,
            signature: [0u8; 65],
        }
    }

    fn make_solution(output: u128, gas: u64) -> Solution {
        let mut buy_amount = [0u8; 32];
        buy_amount[16..32].copy_from_slice(&output.to_be_bytes());
        Solution {
            intent_id: IntentId([0u8; 32]),
            route: vec![],
            buy_amount,
            gas_cost: gas,
            solver: [0u8; 20],
        }
    }

    #[test]
    fn test_auction_selects_best_output() {
        let mut auction = DutchAuction::new(make_intent(), Some(5000));
        auction
            .submit_solution([1u8; 20], make_solution(950, 50_000))
            .unwrap();
        auction
            .submit_solution([2u8; 20], make_solution(980, 60_000))
            .unwrap();
        auction
            .submit_solution([3u8; 20], make_solution(970, 40_000))
            .unwrap();

        let winner = auction.finalize().unwrap();
        assert_eq!(winner.solver_id, [2u8; 20]);
    }

    #[test]
    fn test_auction_no_submissions() {
        let mut auction = DutchAuction::new(make_intent(), Some(5000));
        assert!(auction.finalize().is_none());
    }
}

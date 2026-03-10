//! Batch auction implementation.
//!
//! Collects intents during an open window, then computes a uniform
//! clearing price and generates fills for all matched intents.

use ari_core::{Batch, BatchResult, BatchStatus, Intent, IntentId, Solution};

use super::pricing;

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

    /// Runs the full batch auction: close -> compute clearing price -> generate fills.
    ///
    /// This is a convenience method that performs all steps in sequence.
    pub fn run_batch(&mut self) -> ari_core::Result<BatchResult> {
        if self.current_batch.status == BatchStatus::Open {
            self.close_batch();
        }
        self.compute_clearing_price()
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

        // Find the uniform clearing price
        let clearing_price = pricing::uniform_clearing_price(&self.intents);

        if clearing_price == 0 && !self.intents.is_empty() {
            // No valid clearing price found — no crossing orders
            self.current_batch.status = BatchStatus::Solved;
            return Ok(BatchResult {
                batch_id: self.current_batch.id,
                solutions: Vec::new(),
                clearing_price: 0,
                total_volume: [0u8; 32],
            });
        }

        // Determine which intents are filled
        let fills = pricing::compute_fills(&self.intents, clearing_price);

        // Generate solutions for each fill
        let mut solutions = Vec::with_capacity(fills.len());
        let mut total_volume = 0u128;

        for (intent_idx, fill_amount) in &fills {
            let intent = &self.intents[*intent_idx];
            let intent_id = self.current_batch.intents[*intent_idx];

            // Compute the buy amount at the clearing price
            // For sellers: buy_amount = fill_amount * clearing_price / Q96
            // For buyers: buy_amount = fill_amount (they receive the base token)
            let q96 = 1u128 << 96;
            let is_sell = intent.sell_token.address < intent.buy_token.address;
            let output_amount = if is_sell {
                // Seller gets clearing_price * sell_amount / Q96 of token1
                clearing_price
                    .checked_mul(*fill_amount)
                    .map(|p| p / q96)
                    .unwrap_or(*fill_amount)
            } else {
                // Buyer gets fill_amount of token0 at clearing_price
                *fill_amount
            };

            let mut buy_amount_bytes = [0u8; 32];
            buy_amount_bytes[16..32].copy_from_slice(&output_amount.to_be_bytes());

            solutions.push(Solution {
                intent_id,
                route: Vec::new(), // Batch auction is a direct cross, no hops
                buy_amount: buy_amount_bytes,
                gas_cost: 0,
                solver: [0u8; 20],
            });

            total_volume = total_volume.saturating_add(*fill_amount);
        }

        self.current_batch.status = BatchStatus::Solved;

        let mut volume_bytes = [0u8; 32];
        volume_bytes[16..32].copy_from_slice(&total_volume.to_be_bytes());

        Ok(BatchResult {
            batch_id: self.current_batch.id,
            solutions,
            clearing_price,
            total_volume: volume_bytes,
        })
    }

    /// Returns a reference to the current batch.
    pub fn current_batch(&self) -> &Batch {
        &self.current_batch
    }

    /// Returns the number of intents in the current batch.
    pub fn intent_count(&self) -> usize {
        self.intents.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::{ChainId, Token};

    fn make_token(addr_byte: u8, symbol: &str) -> Token {
        let mut address = [0u8; 20];
        address[0] = addr_byte;
        Token {
            chain: ChainId::Ethereum,
            address,
            symbol: symbol.to_string(),
            decimals: 18,
        }
    }

    fn make_intent(
        sell_token: Token,
        buy_token: Token,
        sell_amount: u128,
        buy_amount: u128,
        nonce: u64,
    ) -> Intent {
        let mut sell_bytes = [0u8; 32];
        sell_bytes[16..32].copy_from_slice(&sell_amount.to_be_bytes());
        let mut buy_bytes = [0u8; 32];
        buy_bytes[16..32].copy_from_slice(&buy_amount.to_be_bytes());

        Intent {
            sender: [0u8; 20],
            sell_token,
            buy_token,
            sell_amount: sell_bytes,
            buy_amount: buy_bytes,
            min_buy: buy_bytes,
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce,
            signature: [0u8; 65],
        }
    }

    #[test]
    fn run_batch_with_matching_intents() {
        let token_a = make_token(1, "A");
        let token_b = make_token(2, "B");

        let mut auction = BatchAuction::new(1, 0, 100);

        // Seller: 100 A for 200 B (min 2 B/A)
        let sell = make_intent(token_a.clone(), token_b.clone(), 100, 200, 1);
        auction.submit_intent(sell).unwrap();

        // Buyer: 300 B for 100 A (max 3 B/A)
        let buy = make_intent(token_b.clone(), token_a.clone(), 300, 100, 2);
        auction.submit_intent(buy).unwrap();

        let result = auction.run_batch().unwrap();
        assert!(result.clearing_price > 0);
        assert!(!result.solutions.is_empty());
    }

    #[test]
    fn run_batch_no_match() {
        let token_a = make_token(1, "A");
        let token_b = make_token(2, "B");

        let mut auction = BatchAuction::new(1, 0, 100);

        // Seller wants 5 B/A minimum
        let sell = make_intent(token_a.clone(), token_b.clone(), 100, 500, 1);
        auction.submit_intent(sell).unwrap();

        // Buyer will pay at most 2 B/A
        let buy = make_intent(token_b.clone(), token_a.clone(), 200, 100, 2);
        auction.submit_intent(buy).unwrap();

        let result = auction.run_batch().unwrap();
        assert_eq!(result.clearing_price, 0);
        assert!(result.solutions.is_empty());
    }

    #[test]
    fn cannot_submit_after_close() {
        let token_a = make_token(1, "A");
        let token_b = make_token(2, "B");

        let mut auction = BatchAuction::new(1, 0, 100);
        auction.close_batch();

        let intent = make_intent(token_a, token_b, 100, 200, 1);
        assert!(auction.submit_intent(intent).is_err());
    }
}

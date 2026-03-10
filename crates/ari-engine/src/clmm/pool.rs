//! Concentrated liquidity pool with swap execution.

use ari_core::{Pool, Token};

/// A concentrated liquidity pool capable of executing swaps.
#[derive(Debug, Clone)]
pub struct ConcentratedPool {
    /// Underlying pool data.
    pub pool: Pool,
}

impl ConcentratedPool {
    /// Creates a new concentrated pool from core pool data.
    pub fn new(pool: Pool) -> Self {
        Self { pool }
    }

    /// Executes a swap against this pool.
    ///
    /// Returns the output amount for the given input.
    ///
    /// # Arguments
    /// * `token_in` - The token being sold
    /// * `amount_in` - Input amount as a u128
    ///
    /// # Returns
    /// The output amount as a u128, or an error.
    pub fn swap(
        &mut self,
        _token_in: &Token,
        _amount_in: u128,
    ) -> ari_core::Result<u128> {
        // TODO: Implement real CLMM swap math (tick traversal, fee calculation)
        Err(ari_core::AriError::InsufficientLiquidity)
    }

    /// Returns the current sqrt price of the pool.
    pub fn sqrt_price(&self) -> u128 {
        self.pool.sqrt_price
    }

    /// Returns the current liquidity of the pool.
    pub fn liquidity(&self) -> u128 {
        self.pool.liquidity
    }
}

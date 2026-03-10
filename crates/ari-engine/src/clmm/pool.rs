//! Concentrated liquidity pool with swap execution.
//!
//! Implements a Uniswap V3-style CLMM pool that crosses ticks and
//! computes output amounts using the math module.

use ari_core::{Pool, Position, Token};

use super::math;
use super::position::PositionManager;

/// Fee rate for the pool in parts-per-million.
/// Maps FeeTier bps: 1 bps = 100 ppm, 5 bps = 500 ppm, 30 bps = 3000 ppm.
fn fee_tier_to_ppm(fee_tier: &ari_core::FeeTier) -> u32 {
    match fee_tier {
        ari_core::FeeTier::Basis1 => 100,
        ari_core::FeeTier::Basis5 => 500,
        ari_core::FeeTier::Basis30 => 3000,
    }
}

/// A concentrated liquidity pool capable of executing swaps.
#[derive(Debug, Clone)]
pub struct ConcentratedPool {
    /// Underlying pool data.
    pub pool: Pool,
    /// Current tick (derived from sqrt_price).
    pub current_tick: i32,
    /// Position manager with tick data and bitmap.
    pub positions: PositionManager,
}

/// Result of a swap execution.
#[derive(Debug, Clone, Copy)]
pub struct SwapResult {
    /// Amount of input token consumed.
    pub amount_in: u128,
    /// Amount of output token produced.
    pub amount_out: u128,
    /// Final sqrt price after the swap.
    pub sqrt_price_after: u128,
    /// Final tick after the swap.
    pub tick_after: i32,
    /// Total fees collected.
    pub fee_amount: u128,
}

impl ConcentratedPool {
    /// Creates a new concentrated pool from core pool data.
    pub fn new(pool: Pool) -> Self {
        let current_tick = math::sqrt_price_to_tick(pool.sqrt_price);
        Self {
            pool,
            current_tick,
            positions: PositionManager::new(),
        }
    }

    /// Adds a liquidity position to the pool.
    ///
    /// Returns the token amounts required from the LP.
    pub fn add_liquidity(&mut self, position: Position) -> (u128, u128) {
        let tick_spacing = self.pool.tick_spacing;
        let sqrt_price = self.pool.sqrt_price;

        // Update in-range liquidity if position overlaps current tick
        if position.tick_lower <= self.current_tick
            && self.current_tick < position.tick_upper
        {
            self.pool.liquidity += position.liquidity;
        }

        let result = self
            .positions
            .add_position(position, sqrt_price, tick_spacing);
        (result.amount0, result.amount1)
    }

    /// Executes a swap against this pool.
    ///
    /// Returns the output amount for the given input.
    ///
    /// # Arguments
    /// * `token_in` - The token being sold
    /// * `amount_in` - Input amount
    ///
    /// # Returns
    /// The output amount, or an error if insufficient liquidity.
    pub fn swap(
        &mut self,
        token_in: &Token,
        amount_in: u128,
    ) -> ari_core::Result<u128> {
        if amount_in == 0 {
            return Ok(0);
        }

        let zero_for_one = token_in == &self.pool.token0;
        let result = self.execute_swap(amount_in, zero_for_one)?;

        Ok(result.amount_out)
    }

    /// Full swap execution with tick crossing.
    fn execute_swap(
        &mut self,
        amount_in: u128,
        zero_for_one: bool,
    ) -> ari_core::Result<SwapResult> {
        let fee_ppm = fee_tier_to_ppm(&self.pool.fee_tier);
        let tick_spacing = self.pool.tick_spacing;

        let sqrt_price_limit = if zero_for_one {
            math::MIN_SQRT_PRICE + 1
        } else {
            math::MAX_SQRT_PRICE - 1
        };

        let mut state = SwapState {
            amount_remaining: amount_in,
            amount_in_total: 0,
            amount_out_total: 0,
            sqrt_price: self.pool.sqrt_price,
            tick: self.current_tick,
            liquidity: self.pool.liquidity,
            fee_total: 0,
        };

        // Maximum iterations to prevent infinite loops
        let max_steps = 100;
        let mut steps = 0;

        while state.amount_remaining > 0 && steps < max_steps {
            steps += 1;

            // Find the next initialized tick
            let next_tick_opt = self
                .positions
                .tick_bitmap
                .next_initialized_tick(state.tick, tick_spacing, zero_for_one);

            let next_tick = match next_tick_opt {
                Some(t) => t,
                None => {
                    // No more initialized ticks; use the price limit
                    if state.amount_in_total == 0 {
                        return Err(ari_core::AriError::InsufficientLiquidity);
                    }
                    break;
                }
            };

            // Clamp to sqrt_price_limit
            let sqrt_price_target = math::tick_to_sqrt_price(next_tick);
            let sqrt_price_target_clamped = if zero_for_one {
                sqrt_price_target.max(sqrt_price_limit)
            } else {
                sqrt_price_target.min(sqrt_price_limit)
            };

            // Can't swap without liquidity
            if state.liquidity == 0 {
                // Move to the next tick
                state.tick = if zero_for_one {
                    next_tick - 1
                } else {
                    next_tick
                };
                state.sqrt_price = sqrt_price_target;
                continue;
            }

            // Compute the swap step
            let (step_in, step_out, sqrt_price_next, step_fee) =
                math::compute_swap_step(
                    state.sqrt_price,
                    sqrt_price_target_clamped,
                    state.liquidity,
                    state.amount_remaining,
                    fee_ppm,
                );

            state.amount_remaining = state
                .amount_remaining
                .saturating_sub(step_in + step_fee);
            state.amount_in_total += step_in;
            state.amount_out_total += step_out;
            state.fee_total += step_fee;
            state.sqrt_price = sqrt_price_next;

            // Check if we reached the target tick
            if sqrt_price_next == sqrt_price_target {
                // Cross the tick: apply liquidity_net
                let liquidity_net =
                    self.positions.tick_map.cross(next_tick);

                if zero_for_one {
                    // Moving left: subtract net (which was added at lower tick)
                    if liquidity_net < 0 {
                        state.liquidity += (-liquidity_net) as u128;
                    } else {
                        state.liquidity =
                            state.liquidity.saturating_sub(liquidity_net as u128);
                    }
                    state.tick = next_tick - 1;
                } else {
                    // Moving right: add net
                    if liquidity_net > 0 {
                        state.liquidity += liquidity_net as u128;
                    } else {
                        state.liquidity = state
                            .liquidity
                            .saturating_sub((-liquidity_net) as u128);
                    }
                    state.tick = next_tick;
                }
            } else {
                // Didn't reach the next tick; we're done
                state.tick = math::sqrt_price_to_tick(state.sqrt_price);
                break;
            }
        }

        // Update pool state
        self.pool.sqrt_price = state.sqrt_price;
        self.current_tick = state.tick;
        self.pool.liquidity = state.liquidity;

        if state.amount_out_total == 0 {
            return Err(ari_core::AriError::InsufficientLiquidity);
        }

        Ok(SwapResult {
            amount_in: state.amount_in_total,
            amount_out: state.amount_out_total,
            sqrt_price_after: state.sqrt_price,
            tick_after: state.tick,
            fee_amount: state.fee_total,
        })
    }

    /// Returns the current sqrt price of the pool.
    pub fn sqrt_price(&self) -> u128 {
        self.pool.sqrt_price
    }

    /// Returns the current liquidity of the pool.
    pub fn liquidity(&self) -> u128 {
        self.pool.liquidity
    }

    /// Returns the current tick.
    pub fn current_tick(&self) -> i32 {
        self.current_tick
    }
}

/// Internal mutable state during swap execution.
struct SwapState {
    amount_remaining: u128,
    amount_in_total: u128,
    amount_out_total: u128,
    sqrt_price: u128,
    tick: i32,
    liquidity: u128,
    fee_total: u128,
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::{FeeTier, Pool, Position, Token};
    use crate::clmm::math;

    fn test_token(symbol: &str) -> Token {
        Token {
            chain: ari_core::ChainId::Ethereum,
            address: [0u8; 20],
            symbol: symbol.to_string(),
            decimals: 18,
        }
    }

    fn make_pool() -> ConcentratedPool {
        let pool = Pool {
            address: [0u8; 20],
            token0: test_token("WETH"),
            token1: test_token("USDC"),
            fee_tier: FeeTier::Basis30,
            tick_spacing: 60,
            sqrt_price: math::tick_to_sqrt_price(0),
            liquidity: 0,
        };
        ConcentratedPool::new(pool)
    }

    #[test]
    fn swap_with_liquidity() {
        let mut pool = make_pool();

        // Add a wide position
        let position = Position {
            owner: [1u8; 20],
            tick_lower: -12000,
            tick_upper: 12000,
            liquidity: 1_000_000_000_000,
        };
        pool.add_liquidity(position);

        assert!(pool.liquidity() > 0);

        // Swap token0 for token1
        let token_in = pool.pool.token0.clone();
        let result = pool.swap(&token_in, 1_000_000);

        assert!(result.is_ok());
        let amount_out = result.unwrap();
        assert!(amount_out > 0, "should get output tokens");
    }

    #[test]
    fn swap_no_liquidity() {
        let mut pool = make_pool();
        let token_in = pool.pool.token0.clone();
        let result = pool.swap(&token_in, 1_000_000);
        assert!(result.is_err());
    }
}

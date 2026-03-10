//! Position management for concentrated liquidity.
//!
//! Handles adding/removing liquidity positions and computing the
//! corresponding token amounts and tick updates.

use ari_core::Position;

use super::math;
use super::tick::{TickBitmap, TickMap};

/// Manages liquidity positions within a pool.
#[derive(Debug, Clone, Default)]
pub struct PositionManager {
    /// All active positions.
    positions: Vec<Position>,
    /// Tick data for the pool.
    pub tick_map: TickMap,
    /// Tick bitmap for efficient traversal.
    pub tick_bitmap: TickBitmap,
}

/// Result of adding liquidity.
#[derive(Debug, Clone, Copy)]
pub struct MintResult {
    /// Amount of token0 required.
    pub amount0: u128,
    /// Amount of token1 required.
    pub amount1: u128,
}

/// Result of removing liquidity.
#[derive(Debug, Clone, Copy)]
pub struct BurnResult {
    /// Amount of token0 returned.
    pub amount0: u128,
    /// Amount of token1 returned.
    pub amount1: u128,
}

impl PositionManager {
    /// Creates a new empty position manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a new liquidity position.
    ///
    /// Updates tick data and bitmap, then returns the token amounts needed.
    pub fn add_position(
        &mut self,
        position: Position,
        sqrt_price_current: u128,
        tick_spacing: i32,
    ) -> MintResult {
        let liquidity = position.liquidity;
        let tick_lower = position.tick_lower;
        let tick_upper = position.tick_upper;

        // Update tick data
        let flipped_lower =
            self.tick_map
                .update(tick_lower, liquidity as i128, false);
        let flipped_upper =
            self.tick_map
                .update(tick_upper, liquidity as i128, true);

        // Update bitmap if ticks were flipped
        if flipped_lower {
            self.tick_bitmap.flip_tick(tick_lower, tick_spacing);
        }
        if flipped_upper {
            self.tick_bitmap.flip_tick(tick_upper, tick_spacing);
        }

        // Compute token amounts based on current price relative to position range
        let sqrt_price_lower = math::tick_to_sqrt_price(tick_lower);
        let sqrt_price_upper = math::tick_to_sqrt_price(tick_upper);

        let (amount0, amount1) = compute_mint_amounts(
            sqrt_price_current,
            sqrt_price_lower,
            sqrt_price_upper,
            liquidity,
        );

        self.positions.push(position);

        MintResult { amount0, amount1 }
    }

    /// Removes liquidity from a position.
    ///
    /// Returns the token amounts to return to the LP.
    pub fn remove_position(
        &mut self,
        index: usize,
        sqrt_price_current: u128,
        tick_spacing: i32,
    ) -> Option<BurnResult> {
        if index >= self.positions.len() {
            return None;
        }

        let position = self.positions.remove(index);
        let liquidity = position.liquidity;
        let tick_lower = position.tick_lower;
        let tick_upper = position.tick_upper;

        // Update tick data (negative delta)
        let flipped_lower =
            self.tick_map
                .update(tick_lower, -(liquidity as i128), false);
        let flipped_upper =
            self.tick_map
                .update(tick_upper, -(liquidity as i128), true);

        if flipped_lower {
            self.tick_bitmap.flip_tick(tick_lower, tick_spacing);
        }
        if flipped_upper {
            self.tick_bitmap.flip_tick(tick_upper, tick_spacing);
        }

        let sqrt_price_lower = math::tick_to_sqrt_price(tick_lower);
        let sqrt_price_upper = math::tick_to_sqrt_price(tick_upper);

        let (amount0, amount1) = compute_mint_amounts(
            sqrt_price_current,
            sqrt_price_lower,
            sqrt_price_upper,
            liquidity,
        );

        Some(BurnResult { amount0, amount1 })
    }

    /// Returns all positions for a given owner.
    pub fn positions_by_owner(&self, owner: &[u8; 20]) -> Vec<&Position> {
        self.positions.iter().filter(|p| &p.owner == owner).collect()
    }

    /// Returns the total number of positions.
    pub fn position_count(&self) -> usize {
        self.positions.len()
    }
}

/// Computes the token amounts needed for a mint (or returned by a burn).
///
/// Three cases depending on where the current price falls relative to
/// the position's tick range:
///
/// 1. Current price below lower: only token0 needed
/// 2. Current price above upper: only token1 needed
/// 3. Current price in range: both tokens needed
fn compute_mint_amounts(
    sqrt_price_current: u128,
    sqrt_price_lower: u128,
    sqrt_price_upper: u128,
    liquidity: u128,
) -> (u128, u128) {
    if sqrt_price_current <= sqrt_price_lower {
        // Below range: only token0
        let amount0 = math::get_amount0_delta(sqrt_price_lower, sqrt_price_upper, liquidity);
        (amount0, 0)
    } else if sqrt_price_current >= sqrt_price_upper {
        // Above range: only token1
        let amount1 = math::get_amount1_delta(sqrt_price_lower, sqrt_price_upper, liquidity);
        (0, amount1)
    } else {
        // In range: both tokens
        let amount0 =
            math::get_amount0_delta(sqrt_price_current, sqrt_price_upper, liquidity);
        let amount1 =
            math::get_amount1_delta(sqrt_price_lower, sqrt_price_current, liquidity);
        (amount0, amount1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::Position;

    #[test]
    fn add_and_remove_position() {
        let mut pm = PositionManager::new();
        let tick_spacing = 10;
        let sqrt_price = math::tick_to_sqrt_price(0);

        let position = Position {
            owner: [1u8; 20],
            tick_lower: -100,
            tick_upper: 100,
            liquidity: 1_000_000_000,
        };

        let mint = pm.add_position(position, sqrt_price, tick_spacing);
        assert!(mint.amount0 > 0);
        assert!(mint.amount1 > 0);
        assert_eq!(pm.position_count(), 1);

        let burn = pm.remove_position(0, sqrt_price, tick_spacing).unwrap();
        assert_eq!(burn.amount0, mint.amount0);
        assert_eq!(burn.amount1, mint.amount1);
        assert_eq!(pm.position_count(), 0);
    }
}

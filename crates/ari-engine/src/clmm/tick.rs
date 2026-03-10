//! Tick bitmap for efficient tick traversal.
//!
//! Ticks are grouped into 256-tick words. Each word is stored as a u256
//! (represented here as two u128 halves). The bitmap allows O(1) lookup
//! of the next initialized tick in either direction within a word.

use std::collections::HashMap;

use ari_core::Tick;

/// Bitmap tracking initialized ticks for efficient traversal.
///
/// Ticks are divided by `tick_spacing` to produce compressed tick indices,
/// then grouped into 256-entry words (word_pos = compressed >> 8,
/// bit_pos = compressed & 0xFF).
///
/// We use `u128` for the lower 128 bits and a second `u128` for the upper
/// 128 bits of each 256-bit word, but for simplicity we use just one `u128`
/// per word (covers 128 ticks per word) which is sufficient for a prototype.
#[derive(Debug, Clone, Default)]
pub struct TickBitmap {
    /// Maps word position to a 128-bit bitmap.
    bitmap: HashMap<i32, u128>,
}

/// Storage for tick data (liquidity_net, liquidity_gross).
#[derive(Debug, Clone, Default)]
pub struct TickMap {
    /// Tick data indexed by tick index.
    ticks: HashMap<i32, Tick>,
}

impl TickBitmap {
    /// Creates an empty tick bitmap.
    pub fn new() -> Self {
        Self::default()
    }

    /// Computes (word_position, bit_position) for a compressed tick.
    fn position(compressed: i32) -> (i32, u8) {
        // Arithmetic right shift for negative values
        let word_pos = compressed >> 7; // divide by 128
        // bit_pos in [0, 127]
        let bit_pos = (compressed & 0x7F) as u8;
        (word_pos, bit_pos)
    }

    /// Toggles a tick's initialized status in the bitmap.
    pub fn flip_tick(&mut self, tick: i32, tick_spacing: i32) {
        assert!(
            tick % tick_spacing == 0,
            "tick must be aligned to tick_spacing"
        );
        let compressed = tick / tick_spacing;
        let (word_pos, bit_pos) = Self::position(compressed);
        let mask = 1u128 << bit_pos;
        let entry = self.bitmap.entry(word_pos).or_insert(0);
        *entry ^= mask;
    }

    /// Finds the next initialized tick within the same word, relative to the
    /// current tick.
    ///
    /// If `zero_for_one` is true (selling token0), search to the left
    /// (lower ticks). Otherwise search to the right (higher ticks).
    ///
    /// Returns `Some((tick, initialized))` where `initialized` indicates
    /// whether the returned tick is actually initialized or just the boundary.
    pub fn next_initialized_tick_within_word(
        &self,
        tick: i32,
        tick_spacing: i32,
        zero_for_one: bool,
    ) -> (i32, bool) {
        let compressed = tick / tick_spacing;
        let (word_pos, bit_pos) = Self::position(compressed);
        let word = self.bitmap.get(&word_pos).copied().unwrap_or(0);

        if zero_for_one {
            // Search to the left (lower bits, including current bit)
            // Mask: all bits at position <= bit_pos
            let mask = if bit_pos >= 127 {
                u128::MAX
            } else {
                (1u128 << (bit_pos + 1)) - 1
            };
            let masked = word & mask;

            if masked != 0 {
                // Highest set bit in masked
                let highest_bit = 127 - masked.leading_zeros() as u8;
                let next_compressed = word_pos * 128 + highest_bit as i32;
                (next_compressed * tick_spacing, true)
            } else {
                // No initialized tick in this word to the left
                let next_compressed = word_pos * 128;
                (next_compressed * tick_spacing, false)
            }
        } else {
            // Search to the right (higher bits, excluding current bit)
            let search_pos = bit_pos + 1;
            if search_pos >= 128 {
                // Need to go to next word
                let next_compressed = (word_pos + 1) * 128;
                return (next_compressed * tick_spacing, false);
            }
            let mask = !((1u128 << search_pos) - 1);
            let masked = word & mask;

            if masked != 0 {
                let lowest_bit = masked.trailing_zeros() as u8;
                let next_compressed = word_pos * 128 + lowest_bit as i32;
                (next_compressed * tick_spacing, true)
            } else {
                // No initialized tick in this word to the right
                let next_compressed = (word_pos + 1) * 128 - 1;
                (next_compressed * tick_spacing, false)
            }
        }
    }

    /// Finds the next initialized tick, searching across multiple words if needed.
    ///
    /// Returns `Some(tick_index)` or `None` if no initialized tick is found
    /// within a reasonable search range.
    pub fn next_initialized_tick(
        &self,
        tick: i32,
        tick_spacing: i32,
        zero_for_one: bool,
    ) -> Option<i32> {
        let max_iterations = 256; // Limit search to avoid infinite loop
        let mut current_tick = tick;

        for _ in 0..max_iterations {
            let (next_tick, initialized) =
                self.next_initialized_tick_within_word(current_tick, tick_spacing, zero_for_one);

            if initialized {
                return Some(next_tick);
            }

            // Move to the next word boundary
            if zero_for_one {
                if next_tick <= super::math::MIN_TICK {
                    return None;
                }
                current_tick = next_tick - tick_spacing;
            } else {
                if next_tick >= super::math::MAX_TICK {
                    return None;
                }
                current_tick = next_tick + tick_spacing;
            }
        }

        None
    }
}

impl TickMap {
    /// Creates a new empty tick map.
    pub fn new() -> Self {
        Self::default()
    }

    /// Gets tick data for the given tick index.
    pub fn get(&self, tick: i32) -> Option<&Tick> {
        self.ticks.get(&tick)
    }

    /// Gets mutable tick data for the given tick index.
    pub fn get_mut(&mut self, tick: i32) -> Option<&mut Tick> {
        self.ticks.get_mut(&tick)
    }

    /// Updates a tick when liquidity is added or removed.
    ///
    /// Returns `true` if the tick was flipped (went from uninitialized to
    /// initialized or vice versa).
    pub fn update(
        &mut self,
        tick: i32,
        liquidity_delta: i128,
        upper: bool,
    ) -> bool {
        let entry = self.ticks.entry(tick).or_insert_with(|| Tick {
            index: tick,
            liquidity_net: 0,
            liquidity_gross: 0,
        });

        let liquidity_gross_before = entry.liquidity_gross;

        // Update gross liquidity
        if liquidity_delta > 0 {
            entry.liquidity_gross = entry
                .liquidity_gross
                .checked_add(liquidity_delta as u128)
                .expect("liquidity overflow");
        } else {
            entry.liquidity_gross = entry
                .liquidity_gross
                .checked_sub((-liquidity_delta) as u128)
                .expect("liquidity underflow");
        }

        // Update net liquidity (sign depends on whether this is upper or lower tick)
        if upper {
            entry.liquidity_net -= liquidity_delta;
        } else {
            entry.liquidity_net += liquidity_delta;
        }

        // Tick is flipped if it transitions between zero and non-zero gross liquidity
        let flipped = (liquidity_gross_before == 0) != (entry.liquidity_gross == 0);

        // Clean up if tick is no longer referenced
        if entry.liquidity_gross == 0 {
            self.ticks.remove(&tick);
        }

        flipped
    }

    /// Crosses a tick, returning the net liquidity to apply.
    pub fn cross(&self, tick: i32) -> i128 {
        self.ticks
            .get(&tick)
            .map(|t| t.liquidity_net)
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flip_and_find() {
        let mut bm = TickBitmap::new();
        let spacing = 10;

        bm.flip_tick(-200, spacing);
        bm.flip_tick(0, spacing);
        bm.flip_tick(100, spacing);

        // Search right from -300
        let next = bm.next_initialized_tick(-300, spacing, false);
        assert_eq!(next, Some(-200));

        // Search left from 50
        let next = bm.next_initialized_tick(50, spacing, true);
        assert_eq!(next, Some(0));
    }

    #[test]
    fn tick_map_update_and_cross() {
        let mut tm = TickMap::new();

        // Add liquidity at lower=-100, upper=100
        let flipped_lower = tm.update(-100, 1000, false);
        let flipped_upper = tm.update(100, 1000, true);
        assert!(flipped_lower);
        assert!(flipped_upper);

        // Check net liquidity
        assert_eq!(tm.cross(-100), 1000);
        assert_eq!(tm.cross(100), -1000);

        // Remove same liquidity
        let flipped_lower = tm.update(-100, -1000, false);
        let flipped_upper = tm.update(100, -1000, true);
        assert!(flipped_lower); // back to zero
        assert!(flipped_upper);
    }
}

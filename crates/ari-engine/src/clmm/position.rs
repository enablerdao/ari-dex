//! Position management for concentrated liquidity.

use ari_core::Position;

/// Manages liquidity positions within a pool.
#[derive(Debug, Clone, Default)]
pub struct PositionManager {
    positions: Vec<Position>,
}

impl PositionManager {
    /// Creates a new empty position manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a new liquidity position.
    pub fn add_position(&mut self, position: Position) {
        self.positions.push(position);
    }

    /// Removes a position by index.
    pub fn remove_position(&mut self, index: usize) -> Option<Position> {
        if index < self.positions.len() {
            Some(self.positions.remove(index))
        } else {
            None
        }
    }

    /// Returns all positions for a given owner.
    pub fn positions_by_owner(&self, owner: &[u8; 20]) -> Vec<&Position> {
        self.positions.iter().filter(|p| &p.owner == owner).collect()
    }
}

//! Liquidity pool types for concentrated liquidity market makers (CLMM).

use serde::{Deserialize, Serialize};

use crate::token::Token;

/// Fee tier for a liquidity pool, expressed in basis points (1 bp = 0.01%).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u32)]
pub enum FeeTier {
    /// 0.01% fee.
    Basis1 = 1,
    /// 0.05% fee.
    Basis5 = 5,
    /// 0.30% fee.
    Basis30 = 30,
}

/// A concentrated liquidity pool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pool {
    /// Pool contract address.
    pub address: [u8; 20],
    /// First token in the pair.
    pub token0: Token,
    /// Second token in the pair.
    pub token1: Token,
    /// Fee tier of the pool.
    pub fee_tier: FeeTier,
    /// Tick spacing (determined by fee tier).
    pub tick_spacing: i32,
    /// Current sqrt price as a Q64.96 fixed-point value (stored as u128).
    pub sqrt_price: u128,
    /// Current total in-range liquidity.
    pub liquidity: u128,
}

/// A discrete price tick in a CLMM pool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tick {
    /// Tick index.
    pub index: i32,
    /// Net liquidity added/removed when crossing this tick.
    pub liquidity_net: i128,
    /// Gross liquidity referencing this tick.
    pub liquidity_gross: u128,
}

/// A liquidity position in a CLMM pool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Position {
    /// Owner address.
    pub owner: [u8; 20],
    /// Lower tick boundary.
    pub tick_lower: i32,
    /// Upper tick boundary.
    pub tick_upper: i32,
    /// Liquidity amount provided.
    pub liquidity: u128,
}

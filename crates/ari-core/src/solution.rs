//! Solution types returned by solvers.

use serde::{Deserialize, Serialize};

use crate::intent::IntentId;
use crate::token::Token;

/// A single hop in a multi-step swap route.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hop {
    /// Pool address to swap through.
    pub pool: [u8; 20],
    /// Token going into the pool.
    pub token_in: Token,
    /// Token coming out of the pool.
    pub token_out: Token,
}

/// A proposed solution for fulfilling an intent.
///
/// Solvers submit solutions that describe the exact execution route
/// and expected output for a given intent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Solution {
    /// The intent this solution fulfills.
    pub intent_id: IntentId,
    /// Ordered list of swap hops forming the route.
    pub route: Vec<Hop>,
    /// Expected buy amount after executing the route (U256, big-endian).
    pub buy_amount: [u8; 32],
    /// Estimated gas cost in native token units.
    pub gas_cost: u64,
    /// Address of the solver that produced this solution.
    pub solver: [u8; 20],
}

//! ARI DEX solver and routing engine.
//!
//! Solvers compete to find the best execution routes for user intents,
//! optimizing for price, gas cost, and execution probability.

pub mod auction;
pub mod router;
pub mod scoring;
pub mod solver;

//! Token and token pair definitions.

use serde::{Deserialize, Serialize};

use crate::chain::ChainId;

/// Represents a fungible token on a specific chain.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Token {
    /// The chain this token lives on.
    pub chain: ChainId,
    /// Contract address (20 bytes for EVM chains).
    pub address: [u8; 20],
    /// Human-readable ticker symbol (e.g. "USDC").
    pub symbol: String,
    /// Number of decimal places (e.g. 18 for ETH, 6 for USDC).
    pub decimals: u8,
}

/// An ordered pair of tokens, commonly used to identify a market.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct TokenPair {
    /// The base token (token0).
    pub base: Token,
    /// The quote token (token1).
    pub quote: Token,
}

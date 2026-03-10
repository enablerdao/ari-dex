//! Intent definitions for the ARI DEX intent-based trading system.
//!
//! An intent represents a user's desired trade outcome without specifying
//! the exact execution path. Solvers compete to fulfill intents optimally.

use serde::{Deserialize, Serialize};

use crate::chain::ChainId;
use crate::token::Token;

/// Unique identifier for an intent, derived from its content hash.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct IntentId(pub [u8; 32]);

/// Lifecycle status of an intent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IntentStatus {
    /// Submitted but not yet processed.
    Pending,
    /// Encrypted and awaiting batch inclusion.
    Encrypted,
    /// Included in a batch auction.
    Batched,
    /// Matched with a solution by a solver.
    Matched,
    /// Successfully settled on-chain.
    Settled,
    /// Passed the deadline without execution.
    Expired,
    /// Explicitly cancelled by the sender.
    Cancelled,
}

/// A trade intent submitted by a user.
///
/// Intents express *what* a user wants (sell X for at least Y of Z)
/// without dictating *how* the trade should be executed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Intent {
    /// The sender's address (20 bytes, EVM-style).
    pub sender: [u8; 20],
    /// Token the user wants to sell.
    pub sell_token: Token,
    /// Token the user wants to buy.
    pub buy_token: Token,
    /// Amount of `sell_token` to sell (U256, big-endian).
    pub sell_amount: [u8; 32],
    /// Desired amount of `buy_token` to receive (U256, big-endian).
    pub buy_amount: [u8; 32],
    /// Minimum acceptable buy amount after slippage (U256, big-endian).
    pub min_buy: [u8; 32],
    /// Unix timestamp after which the intent expires.
    pub deadline: u64,
    /// Source chain where `sell_token` resides.
    pub src_chain: ChainId,
    /// Destination chain for `buy_token` (None if same-chain).
    pub dst_chain: Option<ChainId>,
    /// Whether the intent can be partially filled.
    pub partial_fill: bool,
    /// Monotonically increasing nonce for replay protection.
    pub nonce: u64,
    /// ECDSA signature over the intent fields (65 bytes: r + s + v).
    #[serde(with = "signature_serde")]
    pub signature: [u8; 65],
}

/// Custom serde support for [u8; 65] since serde only implements for arrays up to 32.
mod signature_serde {
    use serde::{self, Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(bytes: &[u8; 65], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_bytes(bytes)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<[u8; 65], D::Error>
    where
        D: Deserializer<'de>,
    {
        let v: Vec<u8> = Vec::deserialize(deserializer)?;
        v.try_into()
            .map_err(|_| serde::de::Error::custom("expected 65 bytes for signature"))
    }
}

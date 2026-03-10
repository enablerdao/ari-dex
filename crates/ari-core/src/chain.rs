//! Chain identifiers and configuration.

use serde::{Deserialize, Serialize};

/// Supported blockchain network identifiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u64)]
pub enum ChainId {
    /// Solana mainnet (uses 0 as a sentinel since Solana has no EVM chain ID).
    Solana = 0,
    /// Ethereum mainnet.
    Ethereum = 1,
    /// Arbitrum One L2.
    Arbitrum = 42161,
    /// Base L2.
    Base = 8453,
}

impl ChainId {
    /// Returns the numeric chain ID value.
    pub fn as_u64(self) -> u64 {
        self as u64
    }

    /// Returns the human-readable chain name.
    pub fn name(self) -> &'static str {
        match self {
            ChainId::Solana => "Solana",
            ChainId::Ethereum => "Ethereum",
            ChainId::Arbitrum => "Arbitrum",
            ChainId::Base => "Base",
        }
    }
}

/// Configuration for a specific blockchain network.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainConfig {
    /// Chain identifier.
    pub chain_id: ChainId,
    /// RPC endpoint URL.
    pub rpc_url: String,
    /// Average block time in milliseconds.
    pub block_time_ms: u64,
    /// Number of confirmations required for finality.
    pub confirmations: u32,
}

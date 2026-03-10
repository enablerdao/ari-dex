//! Error types for the ARI DEX.

use thiserror::Error;

/// Top-level error type for all ARI operations.
#[derive(Debug, Error)]
pub enum AriError {
    /// The submitted intent has invalid or missing fields.
    #[error("invalid intent: {0}")]
    InvalidIntent(String),

    /// The intent's deadline has passed.
    #[error("intent has expired")]
    ExpiredIntent,

    /// Not enough liquidity to fulfill the trade.
    #[error("insufficient liquidity")]
    InsufficientLiquidity,

    /// The execution price exceeds the user's slippage tolerance.
    #[error("slippage exceeded: expected {expected}, got {actual}")]
    SlippageExceeded {
        /// Expected minimum output.
        expected: u128,
        /// Actual output.
        actual: u128,
    },

    /// The intent signature is invalid or does not match the sender.
    #[error("invalid signature")]
    InvalidSignature,

    /// The specified chain is not supported.
    #[error("chain not supported: {0}")]
    ChainNotSupported(String),

    /// The batch is closed and no longer accepting intents.
    #[error("batch is closed")]
    BatchClosed,

    /// A solver encountered an error while computing a solution.
    #[error("solver error: {0}")]
    SolverError(String),

    /// An unexpected internal error.
    #[error("internal error: {0}")]
    InternalError(String),
}

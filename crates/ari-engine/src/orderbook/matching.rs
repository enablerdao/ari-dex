//! Order matching engine.

use ari_core::LimitOrder;

/// Result of matching two orders.
#[derive(Debug, Clone)]
pub struct MatchResult {
    /// ID of the buy-side order.
    pub buy_order_id: u64,
    /// ID of the sell-side order.
    pub sell_order_id: u64,
    /// Execution price (Q64.96).
    pub execution_price: u128,
    /// Matched quantity (U256, big-endian).
    pub quantity: [u8; 32],
}

/// Determines if two orders can be matched (price crosses).
pub fn can_match(bid: &LimitOrder, ask: &LimitOrder) -> bool {
    bid.price >= ask.price
}

/// Computes the execution price for two crossing orders.
///
/// Uses the price of the resting (earlier) order.
pub fn execution_price(bid: &LimitOrder, ask: &LimitOrder) -> u128 {
    // Price-time priority: earlier order's price wins
    if bid.timestamp <= ask.timestamp {
        bid.price
    } else {
        ask.price
    }
}

//! Batch pricing algorithms.
//!
//! Implements uniform clearing price discovery by aggregating
//! supply and demand curves from intents and finding their intersection.

use ari_core::Intent;

/// Q96 constant for price representation.
const Q96: u128 = 1u128 << 96;

/// An order point on the supply/demand curve.
#[derive(Debug, Clone, Copy)]
struct CurvePoint {
    /// Price as a Q64.96 fixed-point value.
    price: u128,
    /// Cumulative quantity at or better than this price.
    cumulative_qty: u128,
}

/// Computes a uniform clearing price for a set of intents.
///
/// All matched intents execute at the same price, eliminating
/// MEV extraction opportunities.
///
/// Algorithm:
/// 1. Separate intents into buy (demand) and sell (supply) sides
/// 2. Compute implied limit price for each intent
/// 3. Build cumulative demand curve (sorted by price descending)
/// 4. Build cumulative supply curve (sorted by price ascending)
/// 5. Find the intersection where cumulative supply >= cumulative demand
///
/// Returns the clearing price as a Q64.96 fixed-point value, or 0 if
/// no clearing price exists.
pub fn uniform_clearing_price(intents: &[Intent]) -> u128 {
    if intents.is_empty() {
        return 0;
    }

    // Separate buy and sell intents and extract price/quantity
    let mut buy_orders: Vec<(u128, u128)> = Vec::new();  // (price, quantity)
    let mut sell_orders: Vec<(u128, u128)> = Vec::new();

    for intent in intents {
        let sell_amount = u128_from_be_bytes(&intent.sell_amount);
        let buy_amount = u128_from_be_bytes(&intent.buy_amount);

        if sell_amount == 0 || buy_amount == 0 {
            continue;
        }

        // We define "price" as: units of token1 per unit of token0,
        // where token0 is the token with the lower address (canonical ordering).
        //
        // For a seller (selling token0 for token1):
        //   They sell sell_amount of token0 and want at least buy_amount of token1.
        //   Min price = buy_amount / sell_amount (in Q96)
        //
        // For a buyer (selling token1 for token0):
        //   They sell sell_amount of token1 to get buy_amount of token0.
        //   Max price = sell_amount / buy_amount (in Q96)

        if intent.sell_token.address < intent.buy_token.address {
            // Selling token0 for token1: supply side
            // Min acceptable price = buy_amount / sell_amount
            let min_price = mul_div_q96(buy_amount, Q96, sell_amount);
            sell_orders.push((min_price, sell_amount));
        } else {
            // Selling token1 for token0: demand side (buying token0)
            // Max acceptable price = sell_amount / buy_amount
            let max_price = mul_div_q96(sell_amount, Q96, buy_amount);
            buy_orders.push((max_price, buy_amount));
        }
    }

    if buy_orders.is_empty() || sell_orders.is_empty() {
        return 0;
    }

    // Build demand curve: sort by price descending, accumulate quantity
    buy_orders.sort_by(|a, b| b.0.cmp(&a.0));
    let demand_curve: Vec<CurvePoint> = build_cumulative_curve(&buy_orders);

    // Build supply curve: sort by price ascending, accumulate quantity
    sell_orders.sort_by(|a, b| a.0.cmp(&b.0));
    let supply_curve: Vec<CurvePoint> = build_cumulative_curve(&sell_orders);

    // Find intersection: the clearing price is where supply meets demand
    find_intersection(&demand_curve, &supply_curve)
}

/// Computes which intents are filled at the given clearing price.
///
/// Returns a vector of (intent_index, fill_amount) pairs.
pub fn compute_fills(intents: &[Intent], clearing_price: u128) -> Vec<(usize, u128)> {
    let mut fills = Vec::new();

    for (i, intent) in intents.iter().enumerate() {
        let sell_amount = u128_from_be_bytes(&intent.sell_amount);
        let buy_amount = u128_from_be_bytes(&intent.buy_amount);

        if sell_amount == 0 || buy_amount == 0 {
            continue;
        }

        let is_sell = intent.sell_token.address < intent.buy_token.address;

        if is_sell {
            // Seller: min price = buy_amount / sell_amount
            let min_price = mul_div_q96(buy_amount, Q96, sell_amount);
            if clearing_price >= min_price {
                fills.push((i, sell_amount));
            }
        } else {
            // Buyer: max price = sell_amount / buy_amount
            let max_price = mul_div_q96(sell_amount, Q96, buy_amount);
            if clearing_price <= max_price {
                fills.push((i, buy_amount));
            }
        }
    }

    fills
}

/// Builds a cumulative quantity curve from sorted (price, qty) pairs.
fn build_cumulative_curve(orders: &[(u128, u128)]) -> Vec<CurvePoint> {
    let mut curve = Vec::with_capacity(orders.len());
    let mut cumulative = 0u128;

    for &(price, qty) in orders {
        cumulative = cumulative.saturating_add(qty);
        curve.push(CurvePoint {
            price,
            cumulative_qty: cumulative,
        });
    }

    curve
}

/// Finds the intersection of demand and supply curves.
///
/// Demand is sorted by price descending (highest first).
/// Supply is sorted by price ascending (lowest first).
///
/// The clearing price is the highest price where cumulative demand
/// still exceeds or equals cumulative supply.
fn find_intersection(
    demand: &[CurvePoint],
    supply: &[CurvePoint],
) -> u128 {
    if demand.is_empty() || supply.is_empty() {
        return 0;
    }

    // The market clears if the highest bid >= lowest ask
    let highest_bid = demand[0].price;
    let lowest_ask = supply[0].price;

    if highest_bid < lowest_ask {
        // No crossing: no clearing price
        return 0;
    }

    // Walk through price levels to find where supply meets demand.
    // Collect all unique prices, check at each level.
    let mut prices: Vec<u128> = demand
        .iter()
        .chain(supply.iter())
        .map(|p| p.price)
        .collect();
    prices.sort();
    prices.dedup();

    let mut best_price = 0u128;
    let mut best_volume = 0u128;

    for &price in &prices {
        // Demand at this price: total quantity from buyers willing to pay >= price
        let demand_qty = demand
            .iter()
            .filter(|p| p.price >= price)
            .map(|p| p.cumulative_qty)
            .last()
            .unwrap_or(0);

        // Supply at this price: total quantity from sellers willing to sell <= price
        let supply_qty = supply
            .iter()
            .filter(|p| p.price <= price)
            .map(|p| p.cumulative_qty)
            .last()
            .unwrap_or(0);

        // Volume that can clear at this price
        let volume = demand_qty.min(supply_qty);

        if volume > best_volume || (volume == best_volume && volume > 0) {
            best_volume = volume;
            best_price = price;
        }
    }

    best_price
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Extracts a u128 from the lower 16 bytes of a big-endian [u8; 32].
fn u128_from_be_bytes(bytes: &[u8; 32]) -> u128 {
    // Use the lower 16 bytes (big-endian)
    let mut buf = [0u8; 16];
    buf.copy_from_slice(&bytes[16..32]);
    u128::from_be_bytes(buf)
}

/// Multiply a * b / divisor in Q96 space, avoiding overflow where possible.
fn mul_div_q96(a: u128, b: u128, divisor: u128) -> u128 {
    if divisor == 0 {
        return 0;
    }
    match a.checked_mul(b) {
        Some(product) => product / divisor,
        None => {
            // Fallback to f64 for very large numbers
            let result = (a as f64) * (b as f64) / (divisor as f64);
            if result >= u128::MAX as f64 {
                u128::MAX
            } else {
                result as u128
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::{ChainId, Intent, Token};

    fn make_token(addr_byte: u8, symbol: &str) -> Token {
        let mut address = [0u8; 20];
        address[0] = addr_byte;
        Token {
            chain: ChainId::Ethereum,
            address,
            symbol: symbol.to_string(),
            decimals: 18,
        }
    }

    fn make_intent(
        sell_token: Token,
        buy_token: Token,
        sell_amount: u128,
        buy_amount: u128,
    ) -> Intent {
        let mut sell_bytes = [0u8; 32];
        sell_bytes[16..32].copy_from_slice(&sell_amount.to_be_bytes());
        let mut buy_bytes = [0u8; 32];
        buy_bytes[16..32].copy_from_slice(&buy_amount.to_be_bytes());

        Intent {
            sender: [0u8; 20],
            sell_token,
            buy_token,
            sell_amount: sell_bytes,
            buy_amount: buy_bytes,
            min_buy: buy_bytes,
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 0,
            signature: [0u8; 65],
        }
    }

    #[test]
    fn clearing_price_basic() {
        let token_a = make_token(1, "A");
        let token_b = make_token(2, "B");

        // Seller: sells 100 A for 200 B (min price = 2 B/A)
        let sell_intent = make_intent(token_a.clone(), token_b.clone(), 100, 200);
        // Buyer: sells 300 B for 100 A (max price = 3 B/A)
        let buy_intent = make_intent(token_b.clone(), token_a.clone(), 300, 100);

        let price = uniform_clearing_price(&[sell_intent, buy_intent]);
        assert!(price > 0, "should find a clearing price");
    }

    #[test]
    fn no_crossing() {
        let token_a = make_token(1, "A");
        let token_b = make_token(2, "B");

        // Seller wants at least 5 B/A
        let sell_intent = make_intent(token_a.clone(), token_b.clone(), 100, 500);
        // Buyer will pay at most 2 B/A
        let buy_intent = make_intent(token_b.clone(), token_a.clone(), 200, 100);

        let price = uniform_clearing_price(&[sell_intent, buy_intent]);
        assert_eq!(price, 0, "no crossing means no clearing price");
    }
}

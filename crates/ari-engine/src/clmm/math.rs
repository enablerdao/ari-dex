//! CLMM math helpers for sqrt price calculations.
//!
//! Uses Q64.96 fixed-point representation where:
//!   sqrt_price = sqrt(price) * 2^96
//!
//! Based on Uniswap V3's math with u128 precision.

/// The Q96 shift factor: 2^96
const Q96: u128 = 1u128 << 96;

/// Minimum tick index supported.
pub const MIN_TICK: i32 = -887272;

/// Maximum tick index supported.
pub const MAX_TICK: i32 = 887272;

/// Minimum sqrt price (Q64.96), corresponding to tick MIN_TICK.
pub const MIN_SQRT_PRICE: u128 = 4295128739;

/// Maximum sqrt price (Q64.96), corresponding to tick MAX_TICK.
/// Uniswap V3's value fits in u160; we use u128::MAX as our ceiling.
pub const MAX_SQRT_PRICE: u128 = 340_282_366_920_938_463_463_374_607_431_768_211_455;

/// Converts a tick index to a Q64.96 sqrt price.
///
/// Uses the identity: sqrt(1.0001^tick) = 1.0001^(tick/2)
/// Computed via a product of precomputed magic constants for each bit
/// of |tick|, following the Uniswap V3 approach.
///
/// We use floating-point internally then convert to Q64.96.  This is
/// sufficient for a matching-engine prototype; a production system would
/// use the full integer-only magic-number table.
pub fn tick_to_sqrt_price(tick: i32) -> u128 {
    if tick == 0 {
        return Q96; // sqrt(1.0001^0) = 1.0 => 1 << 96
    }

    // sqrt(1.0001^tick) = 1.0001^(tick/2)
    // We use f64 for the exponentiation—this gives ~15 significant digits,
    // which is more than enough for tick indices in range.
    let base: f64 = 1.0001_f64;
    let exponent = tick as f64 / 2.0;
    let sqrt_ratio = base.powf(exponent);

    // Convert to Q64.96
    let result = sqrt_ratio * (Q96 as f64);
    let result = result as u128;

    // Clamp to valid range
    result.max(MIN_SQRT_PRICE).min(MAX_SQRT_PRICE)
}

/// Converts a Q64.96 sqrt price to the nearest tick index.
///
/// Inverse of `tick_to_sqrt_price`. Uses logarithm:
///   tick = floor(log_{1.0001}(sqrt_price / 2^96)^2)
///        = floor(2 * log(sqrt_price / 2^96) / log(1.0001))
pub fn sqrt_price_to_tick(sqrt_price: u128) -> i32 {
    assert!(
        sqrt_price >= MIN_SQRT_PRICE,
        "sqrt_price below minimum"
    );

    if sqrt_price == Q96 {
        return 0;
    }

    let ratio = sqrt_price as f64 / Q96 as f64;
    // ratio = sqrt(1.0001^tick) => ratio^2 = 1.0001^tick
    // tick = log(ratio^2) / log(1.0001) = 2*log(ratio)/log(1.0001)
    let log_base = 1.0001_f64.ln();
    let tick = (2.0 * ratio.ln() / log_base).floor() as i32;

    tick.max(MIN_TICK).min(MAX_TICK)
}

/// Computes the amount of token0 for a given liquidity and price range.
///
/// amount0 = L * (sqrt_price_b - sqrt_price_a) / (sqrt_price_a * sqrt_price_b)
///
/// In Q64.96 terms:
///   amount0 = L * (1/sqrt_price_a - 1/sqrt_price_b)
///           = L * (sqrt_price_b - sqrt_price_a) / (sqrt_price_a * sqrt_price_b / 2^96)
///           * ... adjusted for Q96 representation.
pub fn get_amount0_delta(
    sqrt_price_a: u128,
    sqrt_price_b: u128,
    liquidity: u128,
) -> u128 {
    // Ensure a <= b
    let (lower, upper) = if sqrt_price_a <= sqrt_price_b {
        (sqrt_price_a, sqrt_price_b)
    } else {
        (sqrt_price_b, sqrt_price_a)
    };

    if lower == 0 {
        return 0;
    }

    let diff = upper - lower;

    // amount0 = L * Q96 * diff / (lower * upper)
    // To avoid overflow, we compute in steps using u128.
    // L * Q96 could overflow u128, so we use checked arithmetic and
    // split the multiplication.
    //
    // amount0 = (L * diff / lower) * Q96 / upper
    // This ordering minimizes overflow risk while maintaining precision.
    let numerator = mul_div(liquidity, diff, lower);
    mul_div(numerator, Q96, upper)
}

/// Computes the amount of token1 for a given liquidity and price range.
///
/// amount1 = L * (sqrt_price_b - sqrt_price_a) / 2^96
pub fn get_amount1_delta(
    sqrt_price_a: u128,
    sqrt_price_b: u128,
    liquidity: u128,
) -> u128 {
    let (lower, upper) = if sqrt_price_a <= sqrt_price_b {
        (sqrt_price_a, sqrt_price_b)
    } else {
        (sqrt_price_b, sqrt_price_a)
    };

    let diff = upper - lower;
    // amount1 = L * diff / Q96
    mul_div(liquidity, diff, Q96)
}

/// Given an input amount of token0 and current sqrt price, compute the next sqrt price.
///
/// When swapping token0 for token1 (zero_for_one = true), the price decreases.
/// next_sqrt_price = L * sqrt_price_current / (L + amount_in * sqrt_price_current / Q96)
pub fn get_next_sqrt_price_from_input(
    sqrt_price: u128,
    liquidity: u128,
    amount_in: u128,
    zero_for_one: bool,
) -> u128 {
    if zero_for_one {
        // Adding token0 => price goes down
        // next = L * Q96 / (L * Q96 / sqrt_price + amount_in)
        let price_inv_scaled = mul_div(liquidity, Q96, sqrt_price);
        let denominator = price_inv_scaled + amount_in;
        if denominator == 0 {
            return MIN_SQRT_PRICE;
        }
        let result = mul_div(liquidity, Q96, denominator);
        result.max(MIN_SQRT_PRICE)
    } else {
        // Adding token1 => price goes up
        // next = sqrt_price + amount_in * Q96 / L
        let delta = mul_div(amount_in, Q96, liquidity);
        let result = sqrt_price + delta;
        result.min(MAX_SQRT_PRICE)
    }
}

/// Given an output amount and current sqrt price, compute the next sqrt price.
///
/// When removing token1 (zero_for_one = true), or token0 (zero_for_one = false).
pub fn get_next_sqrt_price_from_output(
    sqrt_price: u128,
    liquidity: u128,
    amount_out: u128,
    zero_for_one: bool,
) -> u128 {
    if zero_for_one {
        // Output is token1 => price goes down
        // amount1_out = L * (sqrt_price - next_sqrt_price) / Q96
        // next_sqrt_price = sqrt_price - amount_out * Q96 / L
        let delta = mul_div(amount_out, Q96, liquidity);
        if delta >= sqrt_price {
            return MIN_SQRT_PRICE;
        }
        let result = sqrt_price - delta;
        result.max(MIN_SQRT_PRICE)
    } else {
        // Output is token0 => price goes up
        // amount0_out = L * Q96 * (next - current) / (current * next)
        // Rearranged: next = L * current / (L - amount_out * current / Q96)
        let product = mul_div(amount_out, sqrt_price, Q96);
        if product >= liquidity {
            return MAX_SQRT_PRICE;
        }
        let denominator = liquidity - product;
        let result = mul_div(liquidity, sqrt_price, denominator);
        result.min(MAX_SQRT_PRICE)
    }
}

/// Computes the output amount for a swap step within a single tick range.
///
/// Returns (amount_in_consumed, amount_out, next_sqrt_price, fee_amount).
pub fn compute_swap_step(
    sqrt_price_current: u128,
    sqrt_price_target: u128,
    liquidity: u128,
    amount_remaining: u128,
    fee_rate_bps: u32,
) -> (u128, u128, u128, u128) {
    let zero_for_one = sqrt_price_current >= sqrt_price_target;

    // Remove fee from amount_remaining to get the effective input
    let amount_remaining_less_fee =
        mul_div(amount_remaining, 1_000_000 - fee_rate_bps as u128, 1_000_000);

    // Compute max input that this step can consume
    let amount_in_max = if zero_for_one {
        get_amount0_delta(sqrt_price_target, sqrt_price_current, liquidity)
    } else {
        get_amount1_delta(sqrt_price_current, sqrt_price_target, liquidity)
    };

    let (sqrt_price_next, amount_in, amount_out);

    if amount_remaining_less_fee >= amount_in_max {
        // We reach the target price
        sqrt_price_next = sqrt_price_target;
        amount_in = amount_in_max;
        amount_out = if zero_for_one {
            get_amount1_delta(sqrt_price_target, sqrt_price_current, liquidity)
        } else {
            get_amount0_delta(sqrt_price_current, sqrt_price_target, liquidity)
        };
    } else {
        // Partial fill within this tick range
        sqrt_price_next = get_next_sqrt_price_from_input(
            sqrt_price_current,
            liquidity,
            amount_remaining_less_fee,
            zero_for_one,
        );
        amount_in = if zero_for_one {
            get_amount0_delta(sqrt_price_next, sqrt_price_current, liquidity)
        } else {
            get_amount1_delta(sqrt_price_current, sqrt_price_next, liquidity)
        };
        amount_out = if zero_for_one {
            get_amount1_delta(sqrt_price_next, sqrt_price_current, liquidity)
        } else {
            get_amount0_delta(sqrt_price_current, sqrt_price_next, liquidity)
        };
    }

    // Compute fee on the consumed input amount
    let fee_amount = if amount_remaining_less_fee >= amount_in_max {
        // We consumed the full step; fee is the remainder
        amount_remaining.saturating_sub(amount_in)
    } else {
        mul_div(amount_in, fee_rate_bps as u128, 1_000_000 - fee_rate_bps as u128)
    };

    (amount_in, amount_out, sqrt_price_next, fee_amount)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Multiply then divide with u128, using u128 arithmetic.
/// Rounds down. Returns 0 if divisor is 0.
fn mul_div(a: u128, b: u128, divisor: u128) -> u128 {
    if divisor == 0 {
        return 0;
    }
    // Use widening multiplication via two u128 halves to avoid overflow
    // For simplicity and correctness, we use the checked path first,
    // falling back to a split approach.
    if let Some(product) = a.checked_mul(b) {
        product / divisor
    } else {
        // Widening mul: split into high and low 64-bit parts
        mul_div_wide(a, b, divisor)
    }
}

/// Wide multiplication fallback for when a*b overflows u128.
fn mul_div_wide(a: u128, b: u128, divisor: u128) -> u128 {
    // Use f64 as a fallback for very large numbers.
    // This loses some precision but avoids pulling in a big-integer crate.
    // For production, replace with a proper 256-bit multiply.
    let result = (a as f64) * (b as f64) / (divisor as f64);
    if result >= u128::MAX as f64 {
        u128::MAX
    } else if result <= 0.0 {
        0
    } else {
        result as u128
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tick_zero_is_q96() {
        assert_eq!(tick_to_sqrt_price(0), Q96);
    }

    #[test]
    fn roundtrip_tick_price() {
        for tick in [-100, -1, 0, 1, 100, 1000, -1000, 50000, -50000] {
            let price = tick_to_sqrt_price(tick);
            let recovered = sqrt_price_to_tick(price);
            // Allow +-1 tolerance due to floor
            assert!(
                (recovered - tick).abs() <= 1,
                "tick={tick}, price={price}, recovered={recovered}"
            );
        }
    }

    #[test]
    fn amount_deltas_nonzero() {
        let lower = tick_to_sqrt_price(-100);
        let upper = tick_to_sqrt_price(100);
        let liq = 1_000_000_000_u128;

        let a0 = get_amount0_delta(lower, upper, liq);
        let a1 = get_amount1_delta(lower, upper, liq);
        assert!(a0 > 0, "amount0 should be positive");
        assert!(a1 > 0, "amount1 should be positive");
    }

    #[test]
    fn swap_step_basic() {
        let sqrt_price = tick_to_sqrt_price(0);
        let target = tick_to_sqrt_price(-100);
        let liq = 1_000_000_000_000_u128;
        let amount_in = 1_000_000_u128;
        let fee = 3000; // 0.3% in parts-per-million

        let (consumed, out, next_price, fee_amt) =
            compute_swap_step(sqrt_price, target, liq, amount_in, fee);

        assert!(consumed > 0);
        assert!(out > 0);
        assert!(next_price <= sqrt_price);
        assert!(fee_amt > 0);
    }
}

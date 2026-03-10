//! Solution quality scoring and ranking.
//!
//! Each solution is scored on a 0–100 scale based on three factors:
//! - Price improvement vs. the intent's requested buy amount
//! - Gas efficiency (lower gas is better)
//! - Execution probability (fewer hops → higher confidence)

use ari_core::{Intent, Solution};

/// Weight for the price improvement factor (0–1).
const PRICE_WEIGHT: f64 = 0.60;
/// Weight for the gas efficiency factor (0–1).
const GAS_WEIGHT: f64 = 0.25;
/// Weight for the execution probability factor (0–1).
const EXEC_WEIGHT: f64 = 0.15;

/// Maximum gas cost used for normalisation (in native units).
const MAX_GAS: f64 = 500_000.0;
/// Maximum hops used for normalisation.
const MAX_HOPS: f64 = 4.0;

/// Scores a solution against its originating intent.
///
/// Returns a value in `[0.0, 100.0]` where higher is better.
pub fn score_solution(intent: &Intent, solution: &Solution) -> f64 {
    let price_score = price_improvement_score(intent, solution);
    let gas_score = gas_efficiency_score(solution);
    let exec_score = execution_probability_score(solution);

    let raw = price_score * PRICE_WEIGHT + gas_score * GAS_WEIGHT + exec_score * EXEC_WEIGHT;

    // Clamp to [0, 100].
    raw.max(0.0).min(100.0)
}

/// Price improvement: how much better the solution's output is compared to the
/// intent's requested `buy_amount`.
///
/// Returns 0–100 where 50 means exactly meeting the quote and 100 means
/// >=10% improvement.
fn price_improvement_score(intent: &Intent, solution: &Solution) -> f64 {
    let quote = u128_from_tail(&intent.buy_amount) as f64;
    let actual = u128_from_tail(&solution.buy_amount) as f64;

    if quote == 0.0 {
        return 50.0;
    }

    let improvement = (actual - quote) / quote;
    // Map [-inf, +inf] improvement ratio to [0, 100].
    // 0% improvement → 50, +10% → 100, -10% → 0
    let score = 50.0 + improvement * 500.0; // 1% → 5 points
    score.max(0.0).min(100.0)
}

/// Gas efficiency: lower gas cost scores higher.
fn gas_efficiency_score(solution: &Solution) -> f64 {
    let gas = solution.gas_cost as f64;
    let normalised = 1.0 - (gas / MAX_GAS).min(1.0);
    normalised * 100.0
}

/// Execution probability: fewer hops → higher probability of success.
fn execution_probability_score(solution: &Solution) -> f64 {
    let hops = solution.route.len() as f64;
    let normalised = 1.0 - (hops / MAX_HOPS).min(1.0);
    normalised * 100.0
}

/// Extract the lower 128 bits from a 32-byte big-endian U256.
fn u128_from_tail(bytes: &[u8; 32]) -> u128 {
    u128::from_be_bytes(bytes[16..32].try_into().unwrap_or([0u8; 16]))
}

/// Rank a set of solutions by score (descending).
pub fn rank_solutions(intent: &Intent, solutions: &[Solution]) -> Vec<(usize, f64)> {
    let mut scored: Vec<(usize, f64)> = solutions
        .iter()
        .enumerate()
        .map(|(i, s)| (i, score_solution(intent, s)))
        .collect();
    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    scored
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::*;

    fn make_intent_and_solution(quote: u128, actual: u128, gas: u64, hops: usize) -> (Intent, Solution) {
        let token = Token {
            chain: ChainId::Ethereum,
            address: [0u8; 20],
            symbol: "T".into(),
            decimals: 18,
        };
        let mut buy_amount_intent = [0u8; 32];
        buy_amount_intent[16..32].copy_from_slice(&quote.to_be_bytes());
        let mut buy_amount_sol = [0u8; 32];
        buy_amount_sol[16..32].copy_from_slice(&actual.to_be_bytes());

        let intent = Intent {
            sender: [0u8; 20],
            sell_token: token.clone(),
            buy_token: token.clone(),
            sell_amount: [0u8; 32],
            buy_amount: buy_amount_intent,
            min_buy: [0u8; 32],
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 0,
            signature: [0u8; 65],
        };

        let route: Vec<Hop> = (0..hops)
            .map(|_| Hop {
                pool: [0u8; 20],
                token_in: token.clone(),
                token_out: token.clone(),
            })
            .collect();

        let solution = Solution {
            intent_id: IntentId([0u8; 32]),
            route,
            buy_amount: buy_amount_sol,
            gas_cost: gas,
            solver: [0u8; 20],
        };

        (intent, solution)
    }

    #[test]
    fn test_perfect_quote_match() {
        let (intent, solution) = make_intent_and_solution(1000, 1000, 100_000, 1);
        let score = score_solution(&intent, &solution);
        assert!(score > 30.0 && score < 80.0, "score = {score}");
    }

    #[test]
    fn test_better_output_higher_score() {
        let (intent, sol_good) = make_intent_and_solution(1000, 1050, 100_000, 1);
        let (_, sol_bad) = make_intent_and_solution(1000, 950, 100_000, 1);
        assert!(score_solution(&intent, &sol_good) > score_solution(&intent, &sol_bad));
    }

    #[test]
    fn test_lower_gas_higher_score() {
        let (intent, sol_cheap) = make_intent_and_solution(1000, 1000, 50_000, 1);
        let (_, sol_expensive) = make_intent_and_solution(1000, 1000, 400_000, 1);
        assert!(score_solution(&intent, &sol_cheap) > score_solution(&intent, &sol_expensive));
    }

    #[test]
    fn test_score_in_range() {
        let (intent, solution) = make_intent_and_solution(1000, 1000, 100_000, 2);
        let score = score_solution(&intent, &solution);
        assert!((0.0..=100.0).contains(&score), "score = {score}");
    }
}

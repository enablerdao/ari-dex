//! Solution scoring and ranking.

use ari_core::Solution;

/// Scores a solution based on multiple criteria.
///
/// Higher scores are better. The scoring considers:
/// - Output amount (higher is better)
/// - Gas efficiency (lower gas cost is better)
/// - Route complexity (fewer hops preferred)
pub fn score_solution(solution: &Solution) -> f64 {
    let output_score = u128::from_be_bytes(
        solution.buy_amount[16..32]
            .try_into()
            .unwrap_or([0u8; 16]),
    ) as f64;

    let gas_penalty = solution.gas_cost as f64 * 0.001;
    let hop_penalty = solution.route.len() as f64 * 100.0;

    output_score - gas_penalty - hop_penalty
}

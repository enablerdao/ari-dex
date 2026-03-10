//! Reference solver implementation.
//!
//! Provides a simple solver that uses the router to find the best route for
//! an intent and packages it as a [`Solution`].

use ari_core::{Hop, Intent, IntentId, Solution};

use crate::router::{find_best_route, PoolInfo};
use crate::scoring::score_solution;

/// A reference solver that finds routes via the router module.
#[derive(Debug)]
pub struct ReferenceSolver {
    /// Address identifying this solver.
    pub solver_address: [u8; 20],
    /// Available pool information the solver uses for routing.
    pools: Vec<PoolInfo>,
}

impl ReferenceSolver {
    /// Creates a new reference solver with the given address and pool set.
    pub fn new(solver_address: [u8; 20], pools: Vec<PoolInfo>) -> Self {
        Self {
            solver_address,
            pools,
        }
    }

    /// Updates the pool set used for routing.
    pub fn update_pools(&mut self, pools: Vec<PoolInfo>) {
        self.pools = pools;
    }

    /// Attempts to solve the given intent by finding the best route.
    ///
    /// Returns `None` if no viable route exists.
    pub fn solve(&self, intent: &Intent) -> Option<Solution> {
        let sell_amount = u128::from_be_bytes(
            intent.sell_amount[16..32]
                .try_into()
                .unwrap_or([0u8; 16]),
        );

        let route = find_best_route(&self.pools, &intent.sell_token, &intent.buy_token, sell_amount)?;

        let mut buy_amount = [0u8; 32];
        buy_amount[16..32].copy_from_slice(&route.estimated_output.to_be_bytes());

        // Check that output meets the minimum buy amount.
        let min_buy = u128::from_be_bytes(
            intent.min_buy[16..32]
                .try_into()
                .unwrap_or([0u8; 16]),
        );
        if route.estimated_output < min_buy {
            return None;
        }

        // Estimate gas: base cost 21k + 30k per hop.
        let gas_cost = 21_000 + 30_000 * route.hops.len() as u64;

        let solution = Solution {
            intent_id: IntentId([0u8; 32]), // Would be derived from intent hash in production.
            route: route
                .hops
                .into_iter()
                .map(|h| Hop {
                    pool: h.pool_address,
                    token_in: h.token_in,
                    token_out: h.token_out,
                })
                .collect(),
            buy_amount,
            gas_cost,
            solver: self.solver_address,
        };

        Some(solution)
    }

    /// Solve and return the quality score alongside the solution.
    pub fn solve_and_score(&self, intent: &Intent) -> Option<(Solution, f64)> {
        let solution = self.solve(intent)?;
        let score = score_solution(intent, &solution);
        Some((solution, score))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::*;

    fn make_token(symbol: &str, addr_byte: u8) -> Token {
        let mut address = [0u8; 20];
        address[0] = addr_byte;
        Token {
            chain: ChainId::Ethereum,
            address,
            symbol: symbol.to_string(),
            decimals: 18,
        }
    }

    #[test]
    fn test_reference_solver() {
        let weth = make_token("WETH", 1);
        let usdc = make_token("USDC", 2);

        let pools = vec![PoolInfo {
            address: [0xAA; 20],
            token0: weth.clone(),
            token1: usdc.clone(),
            fee_bps: 30,
            sqrt_price: 1 << 96,
            liquidity: 1_000_000,
        }];

        let solver = ReferenceSolver::new([0x01; 20], pools);

        let mut sell_amount = [0u8; 32];
        sell_amount[16..32].copy_from_slice(&1000u128.to_be_bytes());

        let intent = Intent {
            sender: [1u8; 20],
            sell_token: weth,
            buy_token: usdc,
            sell_amount,
            buy_amount: [0u8; 32],
            min_buy: [0u8; 32], // no minimum
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 0,
            signature: [0u8; 65],
        };

        let solution = solver.solve(&intent);
        assert!(solution.is_some());
        let sol = solution.unwrap();
        assert_eq!(sol.solver, [0x01; 20]);
        assert!(!sol.route.is_empty());

        let output = u128::from_be_bytes(sol.buy_amount[16..32].try_into().unwrap());
        assert!(output > 0);
    }

    #[test]
    fn test_solver_respects_min_buy() {
        let weth = make_token("WETH", 1);
        let usdc = make_token("USDC", 2);

        let pools = vec![PoolInfo {
            address: [0xAA; 20],
            token0: weth.clone(),
            token1: usdc.clone(),
            fee_bps: 30,
            sqrt_price: 1 << 96,
            liquidity: 1_000_000,
        }];

        let solver = ReferenceSolver::new([0x01; 20], pools);

        let mut sell_amount = [0u8; 32];
        sell_amount[16..32].copy_from_slice(&1000u128.to_be_bytes());
        // Set absurdly high min_buy that cannot be met.
        let mut min_buy = [0u8; 32];
        min_buy[16..32].copy_from_slice(&u128::MAX.to_be_bytes());

        let intent = Intent {
            sender: [1u8; 20],
            sell_token: weth,
            buy_token: usdc,
            sell_amount,
            buy_amount: [0u8; 32],
            min_buy,
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 0,
            signature: [0u8; 65],
        };

        assert!(solver.solve(&intent).is_none());
    }
}

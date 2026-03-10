//! Multi-hop route finding across liquidity pools.
//!
//! Uses Dijkstra's algorithm to find the optimal swap path through available
//! pools, supporting up to 3 hops. Each edge weight incorporates fees and
//! estimated price impact so the algorithm naturally favours the cheapest route.

use std::collections::{BinaryHeap, HashMap};
use std::cmp::Ordering;

use ari_core::{Intent, Solution, Hop, Token};

/// Information about a pool used for routing.
#[derive(Debug, Clone)]
pub struct PoolInfo {
    /// Pool address.
    pub address: [u8; 20],
    /// First token.
    pub token0: Token,
    /// Second token.
    pub token1: Token,
    /// Fee in basis points (e.g. 30 = 0.30%).
    pub fee_bps: u32,
    /// Current sqrt price (Q64.96 representation stored as u128).
    pub sqrt_price: u128,
    /// Available liquidity.
    pub liquidity: u128,
}

/// A computed swap route.
#[derive(Debug, Clone)]
pub struct Route {
    /// Ordered hops from sell token to buy token.
    pub hops: Vec<RouteHop>,
    /// Estimated output amount.
    pub estimated_output: u128,
    /// Total fee cost in basis points.
    pub total_fee_bps: u32,
}

/// A single hop in a route.
#[derive(Debug, Clone)]
pub struct RouteHop {
    pub pool_address: [u8; 20],
    pub token_in: Token,
    pub token_out: Token,
    pub fee_bps: u32,
}

/// Maximum number of hops allowed in a route.
const MAX_HOPS: usize = 3;

/// State used in the Dijkstra priority queue.
/// "Cost" is negative output amount so that the max-heap finds the best output.
#[derive(Clone)]
struct State {
    /// Effective output amount at this node.
    output: u128,
    /// Current token we hold.
    token: Token,
    /// Hops taken so far.
    hops: Vec<RouteHop>,
}

impl PartialEq for State {
    fn eq(&self, other: &Self) -> bool {
        self.output == other.output
    }
}
impl Eq for State {}

impl Ord for State {
    fn cmp(&self, other: &Self) -> Ordering {
        // Higher output is better — max-heap behaviour.
        self.output.cmp(&other.output)
    }
}
impl PartialOrd for State {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Build adjacency list: token -> list of (neighbour_token, pool_info).
fn build_graph(pools: &[PoolInfo]) -> HashMap<Token, Vec<(Token, &PoolInfo)>> {
    let mut graph: HashMap<Token, Vec<(Token, &PoolInfo)>> = HashMap::new();
    for pool in pools {
        graph
            .entry(pool.token0.clone())
            .or_default()
            .push((pool.token1.clone(), pool));
        graph
            .entry(pool.token1.clone())
            .or_default()
            .push((pool.token0.clone(), pool));
    }
    graph
}

/// Estimate output amount for a swap through a pool.
///
/// Simplified constant-product model: `out = (amount * (10000 - fee)) / 10000`
/// with a price-impact discount based on pool liquidity.
fn estimate_swap_output(amount: u128, pool: &PoolInfo) -> u128 {
    if pool.liquidity == 0 {
        return 0;
    }
    let after_fee = amount * (10_000 - pool.fee_bps as u128) / 10_000;
    // Simple price-impact model: impact = amount / (liquidity + amount)
    // output = after_fee * liquidity / (liquidity + amount)
    let output = after_fee
        .checked_mul(pool.liquidity)
        .unwrap_or(0)
        / (pool.liquidity.saturating_add(amount));
    output
}

/// Finds the best route from `sell_token` to `buy_token` across `pools`.
///
/// Uses a modified Dijkstra traversal that maximises output amount.
/// Supports up to [`MAX_HOPS`] intermediate swaps.
pub fn find_best_route(
    pools: &[PoolInfo],
    sell_token: &Token,
    buy_token: &Token,
    amount: u128,
) -> Option<Route> {
    let graph = build_graph(pools);

    let mut heap = BinaryHeap::new();
    let mut best_route: Option<Route> = None;

    heap.push(State {
        output: amount,
        token: sell_token.clone(),
        hops: Vec::new(),
    });

    while let Some(state) = heap.pop() {
        // If we reached the target token, record if best.
        if state.token == *buy_token && !state.hops.is_empty() {
            let total_fee: u32 = state.hops.iter().map(|h| h.fee_bps).sum();
            let is_better = best_route
                .as_ref()
                .map_or(true, |r| state.output > r.estimated_output);
            if is_better {
                best_route = Some(Route {
                    hops: state.hops.clone(),
                    estimated_output: state.output,
                    total_fee_bps: total_fee,
                });
            }
            continue;
        }

        // Don't exceed max hops.
        if state.hops.len() >= MAX_HOPS {
            continue;
        }

        if let Some(neighbours) = graph.get(&state.token) {
            for (next_token, pool) in neighbours {
                // Avoid revisiting a token already in our path.
                let already_visited = state.hops.iter().any(|h| h.token_out == *next_token);
                if already_visited {
                    continue;
                }

                let out = estimate_swap_output(state.output, pool);
                if out == 0 {
                    continue;
                }

                let mut new_hops = state.hops.clone();
                new_hops.push(RouteHop {
                    pool_address: pool.address,
                    token_in: state.token.clone(),
                    token_out: next_token.clone(),
                    fee_bps: pool.fee_bps,
                });

                heap.push(State {
                    output: out,
                    token: next_token.clone(),
                    hops: new_hops,
                });
            }
        }
    }

    best_route
}

/// Convenience wrapper that builds a [`Solution`] from an [`Intent`] given
/// available pools.
pub fn find_best_route_for_intent(
    pools: &[PoolInfo],
    intent: &Intent,
) -> ari_core::Result<Solution> {
    let amount = u128::from_be_bytes(
        intent.sell_amount[16..32]
            .try_into()
            .unwrap_or([0u8; 16]),
    );

    let route = find_best_route(pools, &intent.sell_token, &intent.buy_token, amount)
        .ok_or(ari_core::AriError::InsufficientLiquidity)?;

    let mut buy_amount = [0u8; 32];
    buy_amount[16..32].copy_from_slice(&route.estimated_output.to_be_bytes());

    Ok(Solution {
        intent_id: ari_core::IntentId([0u8; 32]),
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
        gas_cost: 21_000 * route.total_fee_bps as u64, // rough estimate
        solver: [0u8; 20],
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use ari_core::ChainId;

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
    fn test_direct_route() {
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

        let route = find_best_route(&pools, &weth, &usdc, 1_000);
        assert!(route.is_some());
        let route = route.unwrap();
        assert_eq!(route.hops.len(), 1);
        assert!(route.estimated_output > 0);
    }

    #[test]
    fn test_multi_hop_route() {
        let weth = make_token("WETH", 1);
        let dai = make_token("DAI", 2);
        let usdc = make_token("USDC", 3);
        let pools = vec![
            PoolInfo {
                address: [0xAA; 20],
                token0: weth.clone(),
                token1: dai.clone(),
                fee_bps: 30,
                sqrt_price: 1 << 96,
                liquidity: 1_000_000,
            },
            PoolInfo {
                address: [0xBB; 20],
                token0: dai.clone(),
                token1: usdc.clone(),
                fee_bps: 5,
                sqrt_price: 1 << 96,
                liquidity: 2_000_000,
            },
        ];

        let route = find_best_route(&pools, &weth, &usdc, 1_000);
        assert!(route.is_some());
        let route = route.unwrap();
        assert_eq!(route.hops.len(), 2);
    }

    #[test]
    fn test_no_route() {
        let weth = make_token("WETH", 1);
        let usdc = make_token("USDC", 2);
        let route = find_best_route(&[], &weth, &usdc, 1_000);
        assert!(route.is_none());
    }
}

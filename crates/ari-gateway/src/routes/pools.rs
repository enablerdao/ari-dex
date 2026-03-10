//! Pool listing endpoint.

use std::sync::Arc;

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::app::AppState;

#[derive(Serialize)]
struct PoolInfo {
    address: String,
    token0: String,
    token1: String,
    fee_tier: u32,
    liquidity: String,
}

#[derive(Serialize)]
struct PoolsResponse {
    pools: Vec<PoolInfo>,
}

async fn list_pools(State(_state): State<Arc<AppState>>) -> Json<PoolsResponse> {
    let pools = vec![
        PoolInfo {
            address: "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640".to_string(),
            token0: "ETH".to_string(),
            token1: "USDC".to_string(),
            fee_tier: 500, // 0.05%
            liquidity: "12500000000000000000000".to_string(),
        },
        PoolInfo {
            address: "0x4e68ccd3e89f51c3074ca5072bbac773960dfa36".to_string(),
            token0: "ETH".to_string(),
            token1: "USDT".to_string(),
            fee_tier: 500, // 0.05%
            liquidity: "8900000000000000000000".to_string(),
        },
        PoolInfo {
            address: "0x3416cf6c708da44db2624d63ea0aaef7113527c6".to_string(),
            token0: "USDC".to_string(),
            token1: "USDT".to_string(),
            fee_tier: 100, // 0.01%
            liquidity: "45000000000000".to_string(),
        },
    ];
    Json(PoolsResponse { pools })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/pools", get(list_pools))
}

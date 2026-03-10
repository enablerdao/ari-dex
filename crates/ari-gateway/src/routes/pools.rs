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
    // TODO: Return actual pools from engine state
    Json(PoolsResponse { pools: Vec::new() })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/pools", get(list_pools))
}

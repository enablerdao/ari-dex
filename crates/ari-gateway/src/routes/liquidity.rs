//! Liquidity management endpoints.

use std::sync::Arc;

use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::AppState;

#[derive(Deserialize)]
struct AddLiquidityRequest {
    pool: String,
    token0_amount: String,
    token1_amount: String,
    tick_lower: i32,
    tick_upper: i32,
}

#[derive(Deserialize)]
struct RemoveLiquidityRequest {
    pool: String,
    position_id: u64,
    liquidity: String,
}

#[derive(Serialize)]
struct LiquidityResponse {
    success: bool,
    message: String,
}

async fn add_liquidity(
    State(_state): State<Arc<AppState>>,
    Json(body): Json<AddLiquidityRequest>,
) -> Json<LiquidityResponse> {
    Json(LiquidityResponse {
        success: true,
        message: format!(
            "Liquidity added to pool {} (tick range [{}, {}])",
            body.pool, body.tick_lower, body.tick_upper
        ),
    })
}

async fn remove_liquidity(
    State(_state): State<Arc<AppState>>,
    Json(body): Json<RemoveLiquidityRequest>,
) -> Json<LiquidityResponse> {
    Json(LiquidityResponse {
        success: true,
        message: format!(
            "Liquidity removed from pool {} (position {})",
            body.pool, body.position_id
        ),
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/liquidity/add", post(add_liquidity))
        .route("/v1/liquidity/remove", post(remove_liquidity))
}

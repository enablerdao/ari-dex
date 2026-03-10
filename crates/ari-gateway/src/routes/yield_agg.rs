//! Yield aggregator endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::AppState;
use crate::db;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct YieldOpportunity {
    strategy_id: String,
    name: String,
    apy: f64,
    protocol: String,
    risk: String,
    token: String,
}

#[derive(Serialize)]
struct YieldsResponse {
    opportunities: Vec<YieldOpportunity>,
}

#[derive(Deserialize)]
struct DepositRequest {
    strategy_id: String,
    amount: String,
    token: String,
    owner: String,
}

#[derive(Serialize)]
struct YieldPosition {
    id: String,
    owner: String,
    strategy_id: String,
    token: String,
    amount: String,
    created_at: u64,
}

#[derive(Serialize)]
struct PositionsResponse {
    address: String,
    positions: Vec<YieldPosition>,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn list_yields(
    State(_state): State<Arc<AppState>>,
) -> Json<YieldsResponse> {
    let opportunities = vec![
        YieldOpportunity {
            strategy_id: "ari-clmm-eth-usdc".to_string(),
            name: "ETH-USDC LP".to_string(),
            apy: 12.5,
            protocol: "ARI CLMM".to_string(),
            risk: "medium".to_string(),
            token: "ETH-USDC".to_string(),
        },
        YieldOpportunity {
            strategy_id: "aave-usdc-lending".to_string(),
            name: "USDC Lending".to_string(),
            apy: 4.2,
            protocol: "Aave".to_string(),
            risk: "low".to_string(),
            token: "USDC".to_string(),
        },
        YieldOpportunity {
            strategy_id: "lido-eth-staking".to_string(),
            name: "ETH Staking".to_string(),
            apy: 3.8,
            protocol: "Lido".to_string(),
            risk: "low".to_string(),
            token: "ETH".to_string(),
        },
        YieldOpportunity {
            strategy_id: "ari-clmm-wbtc-eth".to_string(),
            name: "WBTC-ETH LP".to_string(),
            apy: 8.1,
            protocol: "ARI CLMM".to_string(),
            risk: "medium".to_string(),
            token: "WBTC-ETH".to_string(),
        },
    ];

    Json(YieldsResponse { opportunities })
}

async fn deposit(
    State(state): State<Arc<AppState>>,
    Json(body): Json<DepositRequest>,
) -> impl IntoResponse {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let position_id = format!("yp-{:016x}{:08x}", now, rand::random::<u32>());

    {
        let conn = state.db.lock().await;
        if let Err(e) = db::insert_yield_position(
            &conn,
            &position_id,
            &body.owner,
            &body.strategy_id,
            &body.token,
            &body.amount,
            now,
        ) {
            tracing::error!("Failed to insert yield position: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "internal error"})),
            )
                .into_response();
        }
    }

    (
        StatusCode::CREATED,
        Json(serde_json::json!({
            "position_id": position_id,
            "strategy_id": body.strategy_id,
            "amount": body.amount,
            "token": body.token,
            "status": "active",
        })),
    )
        .into_response()
}

async fn get_positions(
    State(state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<PositionsResponse> {
    let positions = {
        let conn = state.db.lock().await;
        match db::list_yield_positions(&conn, &address) {
            Ok(rows) => rows
                .into_iter()
                .map(|r| YieldPosition {
                    id: r.0,
                    owner: r.1,
                    strategy_id: r.2,
                    token: r.3,
                    amount: r.4,
                    created_at: r.5,
                })
                .collect(),
            Err(e) => {
                tracing::error!("Failed to query yield positions: {e}");
                Vec::new()
            }
        }
    };

    Json(PositionsResponse { address, positions })
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/yields", get(list_yields))
        .route("/v1/yields/deposit", post(deposit))
        .route("/v1/yields/positions/:address", get(get_positions))
}

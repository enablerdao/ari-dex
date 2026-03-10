//! Trade history endpoint.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::app::AppState;

#[derive(Serialize)]
struct TradeRecord {
    intent_id: String,
    sell_token: String,
    buy_token: String,
    sell_amount: String,
    buy_amount: String,
    timestamp: u64,
    status: String,
}

#[derive(Serialize)]
struct HistoryResponse {
    address: String,
    trades: Vec<TradeRecord>,
}

async fn get_history(
    State(_state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<HistoryResponse> {
    // TODO: Look up trade history for address
    Json(HistoryResponse {
        address,
        trades: Vec::new(),
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/history/:address", get(get_history))
}

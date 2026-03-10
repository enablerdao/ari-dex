//! Trade history endpoint.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::app::AppState;
use crate::db;

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
    State(state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<HistoryResponse> {
    let trades = {
        let conn = state.db.lock().unwrap();
        match db::list_intents_by_sender(&conn, &address, Some("settled")) {
            Ok(intents) => intents
                .into_iter()
                .map(|i| TradeRecord {
                    intent_id: i.intent_id,
                    sell_token: i.sell_token,
                    buy_token: i.buy_token,
                    sell_amount: i.sell_amount,
                    buy_amount: i.min_buy_amount,
                    timestamp: i.created_at,
                    status: i.status,
                })
                .collect(),
            Err(e) => {
                tracing::error!("Failed to query history: {e}");
                Vec::new()
            }
        }
    };

    Json(HistoryResponse { address, trades })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/history/:address", get(get_history))
}

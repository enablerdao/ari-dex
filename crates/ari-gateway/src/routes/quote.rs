//! Quote endpoint for price estimation.

use std::sync::Arc;

use axum::extract::{Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::AppState;

#[derive(Deserialize)]
struct QuoteRequest {
    sell_token: String,
    buy_token: String,
    sell_amount: String,
}

#[derive(Serialize)]
struct QuoteResponse {
    sell_token: String,
    buy_token: String,
    sell_amount: String,
    buy_amount: String,
    price: String,
    price_impact: String,
    route: Vec<String>,
}

async fn get_quote(
    State(_state): State<Arc<AppState>>,
    Query(params): Query<QuoteRequest>,
) -> Json<QuoteResponse> {
    // TODO: Compute real quote from engine state
    Json(QuoteResponse {
        sell_token: params.sell_token,
        buy_token: params.buy_token,
        sell_amount: params.sell_amount,
        buy_amount: "0".to_string(),
        price: "0".to_string(),
        price_impact: "0".to_string(),
        route: Vec::new(),
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/quote", get(get_quote))
}

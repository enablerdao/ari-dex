//! Token listing endpoint.

use std::sync::Arc;

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::app::AppState;

#[derive(Serialize)]
struct TokenInfo {
    symbol: String,
    address: String,
    chain: String,
    decimals: u8,
}

#[derive(Serialize)]
struct TokensResponse {
    tokens: Vec<TokenInfo>,
}

async fn list_tokens(State(_state): State<Arc<AppState>>) -> Json<TokensResponse> {
    // TODO: Return registered tokens
    Json(TokensResponse {
        tokens: Vec::new(),
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/tokens", get(list_tokens))
}

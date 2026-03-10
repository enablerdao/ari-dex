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
    let tokens = vec![
        TokenInfo {
            symbol: "ETH".to_string(),
            address: "0x0000000000000000000000000000000000000000".to_string(),
            chain: "ethereum".to_string(),
            decimals: 18,
        },
        TokenInfo {
            symbol: "USDC".to_string(),
            address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(),
            chain: "ethereum".to_string(),
            decimals: 6,
        },
        TokenInfo {
            symbol: "USDT".to_string(),
            address: "0xdAC17F958D2ee523a2206206994597C13D831ec7".to_string(),
            chain: "ethereum".to_string(),
            decimals: 6,
        },
        TokenInfo {
            symbol: "DAI".to_string(),
            address: "0x6B175474E89094C44Da98b954EedeAC495271d0F".to_string(),
            chain: "ethereum".to_string(),
            decimals: 18,
        },
        TokenInfo {
            symbol: "WBTC".to_string(),
            address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599".to_string(),
            chain: "ethereum".to_string(),
            decimals: 8,
        },
    ];
    Json(TokensResponse { tokens })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/tokens", get(list_tokens))
}

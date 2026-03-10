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

/// Mock price table: returns price of `token` in USDC.
fn mock_price_usd(token: &str) -> f64 {
    match token.to_uppercase().as_str() {
        "ETH" => 3500.0,
        "WBTC" => 62000.0,
        "USDC" => 1.0,
        "USDT" => 1.0,
        "DAI" => 1.0,
        _ => 0.0,
    }
}

fn token_decimals(token: &str) -> u32 {
    match token.to_uppercase().as_str() {
        "ETH" | "DAI" => 18,
        "USDC" | "USDT" => 6,
        "WBTC" => 8,
        _ => 18,
    }
}

async fn get_quote(
    State(_state): State<Arc<AppState>>,
    Query(params): Query<QuoteRequest>,
) -> Json<QuoteResponse> {
    let sell_price = mock_price_usd(&params.sell_token);
    let buy_price = mock_price_usd(&params.buy_token);

    let sell_decimals = token_decimals(&params.sell_token);
    let sell_amount_raw: f64 = params.sell_amount.parse().unwrap_or(0.0);
    let sell_amount_human = sell_amount_raw / 10f64.powi(sell_decimals as i32);

    let (buy_amount_human, price, price_impact) = if buy_price > 0.0 {
        let rate = sell_price / buy_price;
        let buy_human = sell_amount_human * rate * 0.9995; // 0.05% fee
        let impact = 0.05 + (sell_amount_human * sell_price / 1_000_000.0) * 0.1; // rough mock
        (buy_human, rate, impact.min(5.0))
    } else {
        (0.0, 0.0, 0.0)
    };

    let buy_decimals = token_decimals(&params.buy_token);
    let buy_amount_raw = buy_amount_human * 10f64.powi(buy_decimals as i32);

    let route = if params.sell_token.to_uppercase() == params.buy_token.to_uppercase() {
        vec![params.sell_token.to_uppercase()]
    } else {
        // Direct pair or via USDC
        let s = params.sell_token.to_uppercase();
        let b = params.buy_token.to_uppercase();
        if s == "USDC" || b == "USDC" || s == "USDT" || b == "USDT" {
            vec![s, b]
        } else {
            vec![s, "USDC".to_string(), b]
        }
    };

    Json(QuoteResponse {
        sell_token: params.sell_token,
        buy_token: params.buy_token,
        sell_amount: params.sell_amount,
        buy_amount: format!("{:.0}", buy_amount_raw),
        price: format!("{:.6}", price),
        price_impact: format!("{:.4}", price_impact),
        route,
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/quote", get(get_quote))
}

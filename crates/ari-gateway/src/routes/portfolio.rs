//! Portfolio rebalancing endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::AppState;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct TargetAllocation {
    token: String,
    percentage: u32,
}

#[derive(Deserialize)]
struct RebalanceRequest {
    owner: String,
    targets: Vec<TargetAllocation>,
}

#[derive(Serialize)]
struct RebalanceIntent {
    sell_token: String,
    buy_token: String,
    sell_amount: String,
    reason: String,
}

#[derive(Serialize)]
struct RebalanceResponse {
    owner: String,
    intents: Vec<RebalanceIntent>,
}

#[derive(Clone, Serialize)]
struct Holding {
    token: String,
    amount: String,
    usd_value: f64,
    percentage: f64,
}

#[derive(Serialize)]
struct PortfolioResponse {
    address: String,
    total_usd: f64,
    holdings: Vec<Holding>,
}

#[derive(Serialize)]
struct DayValue {
    date: String,
    usd_value: f64,
}

#[derive(Serialize)]
struct HistoryResponse {
    address: String,
    days: Vec<DayValue>,
}

// ---------------------------------------------------------------------------
// Mock helpers
// ---------------------------------------------------------------------------

fn mock_holdings() -> Vec<Holding> {
    vec![
        Holding {
            token: "ETH".to_string(),
            amount: "5.0".to_string(),
            usd_value: 10_000.0,
            percentage: 40.0,
        },
        Holding {
            token: "USDC".to_string(),
            amount: "7500".to_string(),
            usd_value: 7_500.0,
            percentage: 30.0,
        },
        Holding {
            token: "WBTC".to_string(),
            amount: "0.12".to_string(),
            usd_value: 5_000.0,
            percentage: 20.0,
        },
        Holding {
            token: "ARB".to_string(),
            amount: "2500".to_string(),
            usd_value: 2_500.0,
            percentage: 10.0,
        },
    ]
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn rebalance(
    State(_state): State<Arc<AppState>>,
    Json(body): Json<RebalanceRequest>,
) -> Json<RebalanceResponse> {
    let holdings = mock_holdings();
    let total_usd: f64 = holdings.iter().map(|h| h.usd_value).sum();

    let mut intents: Vec<RebalanceIntent> = Vec::new();

    for target in &body.targets {
        let current = holdings
            .iter()
            .find(|h| h.token == target.token)
            .map(|h| h.percentage)
            .unwrap_or(0.0);

        let diff = target.percentage as f64 - current;

        if diff.abs() < 1.0 {
            continue; // close enough
        }

        let usd_delta = (diff / 100.0) * total_usd;

        if usd_delta > 0.0 {
            // Need to buy this token — sell USDC for it
            intents.push(RebalanceIntent {
                sell_token: "USDC".to_string(),
                buy_token: target.token.clone(),
                sell_amount: format!("{:.2}", usd_delta),
                reason: format!(
                    "Increase {} from {:.1}% to {}%",
                    target.token, current, target.percentage
                ),
            });
        } else {
            // Need to sell this token for USDC
            intents.push(RebalanceIntent {
                sell_token: target.token.clone(),
                buy_token: "USDC".to_string(),
                sell_amount: format!("{:.2}", usd_delta.abs()),
                reason: format!(
                    "Decrease {} from {:.1}% to {}%",
                    target.token, current, target.percentage
                ),
            });
        }
    }

    Json(RebalanceResponse {
        owner: body.owner,
        intents,
    })
}

async fn get_portfolio(
    State(_state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<PortfolioResponse> {
    let holdings = mock_holdings();
    let total_usd: f64 = holdings.iter().map(|h| h.usd_value).sum();

    Json(PortfolioResponse {
        address,
        total_usd,
        holdings,
    })
}

async fn portfolio_history(
    State(_state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<HistoryResponse> {
    // Mock: last 30 days of portfolio value, slight upward trend
    let base = 24_000.0_f64;
    let days: Vec<DayValue> = (0..30)
        .map(|i| {
            let date = format!("2026-02-{:02}", (i % 28) + 1);
            let noise = ((i as f64) * 0.7).sin() * 500.0;
            DayValue {
                date,
                usd_value: base + (i as f64) * 30.0 + noise,
            }
        })
        .collect();

    Json(HistoryResponse { address, days })
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/portfolio/rebalance", post(rebalance))
        .route("/v1/portfolio/:address", get(get_portfolio))
        .route("/v1/portfolio/:address/history", get(portfolio_history))
}

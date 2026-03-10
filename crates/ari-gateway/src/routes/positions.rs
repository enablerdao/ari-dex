//! NFT LP position dashboard endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::app::AppState;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Clone, Serialize)]
struct LpPosition {
    position_id: u64,
    pool: String,
    token0: String,
    token1: String,
    fee_tier: u32,
    tick_lower: i32,
    tick_upper: i32,
    liquidity: String,
    token0_amount: String,
    token1_amount: String,
    fees_earned: FeesEarned,
    in_range: bool,
}

#[derive(Clone, Serialize)]
struct FeesEarned {
    token0: String,
    token1: String,
    usd: f64,
}

#[derive(Serialize)]
struct PositionsResponse {
    address: String,
    positions: Vec<LpPosition>,
}

#[derive(Serialize)]
struct DayPerformance {
    date: String,
    fees_usd: f64,
    value_usd: f64,
}

#[derive(Serialize)]
struct PositionDetailResponse {
    position: LpPosition,
    performance: Vec<DayPerformance>,
}

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

fn mock_positions() -> Vec<LpPosition> {
    vec![
        LpPosition {
            position_id: 482_371,
            pool: "ETH-USDC 0.05%".to_string(),
            token0: "ETH".to_string(),
            token1: "USDC".to_string(),
            fee_tier: 500,
            tick_lower: 192_200,
            tick_upper: 198_400,
            liquidity: "5200000000000000".to_string(),
            token0_amount: "2.15".to_string(),
            token1_amount: "3820.50".to_string(),
            fees_earned: FeesEarned {
                token0: "0.032".to_string(),
                token1: "58.12".to_string(),
                usd: 122.40,
            },
            in_range: true,
        },
        LpPosition {
            position_id: 510_042,
            pool: "WBTC-ETH 0.3%".to_string(),
            token0: "WBTC".to_string(),
            token1: "ETH".to_string(),
            fee_tier: 3000,
            tick_lower: 253_000,
            tick_upper: 259_000,
            liquidity: "890000000000000".to_string(),
            token0_amount: "0.08".to_string(),
            token1_amount: "1.25".to_string(),
            fees_earned: FeesEarned {
                token0: "0.001".to_string(),
                token1: "0.018".to_string(),
                usd: 71.20,
            },
            in_range: true,
        },
        LpPosition {
            position_id: 493_118,
            pool: "USDC-USDT 0.01%".to_string(),
            token0: "USDC".to_string(),
            token1: "USDT".to_string(),
            fee_tier: 100,
            tick_lower: -10,
            tick_upper: 10,
            liquidity: "12000000000000".to_string(),
            token0_amount: "5000.00".to_string(),
            token1_amount: "5012.30".to_string(),
            fees_earned: FeesEarned {
                token0: "12.50".to_string(),
                token1: "11.80".to_string(),
                usd: 24.30,
            },
            in_range: true,
        },
        LpPosition {
            position_id: 475_290,
            pool: "ETH-USDC 0.3%".to_string(),
            token0: "ETH".to_string(),
            token1: "USDC".to_string(),
            fee_tier: 3000,
            tick_lower: 180_000,
            tick_upper: 185_000,
            liquidity: "3100000000000000".to_string(),
            token0_amount: "3.80".to_string(),
            token1_amount: "0.00".to_string(),
            fees_earned: FeesEarned {
                token0: "0.045".to_string(),
                token1: "0.00".to_string(),
                usd: 90.00,
            },
            in_range: false,
        },
    ]
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn list_positions(
    State(_state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<PositionsResponse> {
    Json(PositionsResponse {
        address,
        positions: mock_positions(),
    })
}

async fn get_position_detail(
    State(_state): State<Arc<AppState>>,
    Path((address, id)): Path<(String, u64)>,
) -> Json<serde_json::Value> {
    let positions = mock_positions();
    let position = positions.into_iter().find(|p| p.position_id == id);

    match position {
        Some(pos) => {
            let performance: Vec<DayPerformance> = (0..30)
                .map(|i| {
                    let date = format!("2026-02-{:02}", (i % 28) + 1);
                    let base_fees = if pos.in_range { 4.0 } else { 0.5 };
                    let noise = ((i as f64) * 1.1).sin() * 1.5;
                    DayPerformance {
                        date,
                        fees_usd: base_fees + noise.abs(),
                        value_usd: 5000.0 + (i as f64) * 10.0 + noise * 100.0,
                    }
                })
                .collect();

            let resp = PositionDetailResponse {
                position: pos,
                performance,
            };
            Json(serde_json::to_value(resp).unwrap())
        }
        None => Json(serde_json::json!({
            "error": "position not found",
            "address": address,
            "position_id": id,
        })),
    }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/positions/:address", get(list_positions))
        .route("/v1/positions/:address/:id", get(get_position_detail))
}

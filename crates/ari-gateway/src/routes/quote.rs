//! Quote endpoint with live price feeds from CoinGecko.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::{Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

use crate::app::AppState;

#[derive(Deserialize)]
struct QuoteRequest {
    sell_token: String,
    buy_token: String,
    sell_amount: String,
}

#[derive(Serialize)]
struct SplitRoute {
    path: Vec<String>,
    percentage: u32,
    buy_amount: String,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    routes: Option<Vec<SplitRoute>>,
}

// ---------------------------------------------------------------------------
// Price cache (refreshed every 30s)
// ---------------------------------------------------------------------------

static PRICE_CACHE: std::sync::OnceLock<Arc<RwLock<PriceCache>>> = std::sync::OnceLock::new();

struct PriceCache {
    prices: HashMap<String, f64>,
    updated_at: Instant,
}

fn cache() -> &'static Arc<RwLock<PriceCache>> {
    PRICE_CACHE.get_or_init(|| {
        Arc::new(RwLock::new(PriceCache {
            prices: default_prices(),
            updated_at: Instant::now() - Duration::from_secs(600), // force first fetch
        }))
    })
}

fn default_prices() -> HashMap<String, f64> {
    let mut m = HashMap::new();
    m.insert("ETH".to_string(), 3500.0);
    m.insert("WBTC".to_string(), 95000.0);
    m.insert("USDC".to_string(), 1.0);
    m.insert("USDT".to_string(), 1.0);
    m.insert("DAI".to_string(), 1.0);
    m
}

async fn refresh_prices() {
    let c = cache();
    {
        let r = c.read().await;
        if r.updated_at.elapsed() < Duration::from_secs(30) {
            return; // fresh enough
        }
    }

    let ids = "ethereum,wrapped-bitcoin,usd-coin,tether,dai";
    let url = format!(
        "https://api.coingecko.com/api/v3/simple/price?ids={}&vs_currencies=usd",
        ids
    );

    let resp = match reqwest::get(&url).await {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("CoinGecko fetch failed: {e}");
            return;
        }
    };

    let data: HashMap<String, HashMap<String, f64>> = match resp.json().await {
        Ok(d) => d,
        Err(e) => {
            tracing::warn!("CoinGecko parse failed: {e}");
            return;
        }
    };

    let mut new_prices = HashMap::new();
    let symbols = [
        ("ethereum", "ETH"),
        ("wrapped-bitcoin", "WBTC"),
        ("usd-coin", "USDC"),
        ("tether", "USDT"),
        ("dai", "DAI"),
    ];
    for (cg_id, sym) in &symbols {
        if let Some(inner) = data.get(*cg_id) {
            if let Some(usd) = inner.get("usd") {
                new_prices.insert(sym.to_string(), *usd);
            }
        }
    }

    if !new_prices.is_empty() {
        let mut w = c.write().await;
        for (k, v) in new_prices {
            w.prices.insert(k, v);
        }
        w.updated_at = Instant::now();
        tracing::info!("Prices updated: {:?}", w.prices);
    }
}

async fn price_usd(token: &str) -> f64 {
    refresh_prices().await;
    let r = cache().read().await;
    r.prices.get(&token.to_uppercase()).copied().unwrap_or(0.0)
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
    let sell_price = price_usd(&params.sell_token).await;
    let buy_price = price_usd(&params.buy_token).await;

    let sell_decimals = token_decimals(&params.sell_token);
    let sell_amount_raw: f64 = params.sell_amount.parse().unwrap_or(0.0);
    let sell_amount_human = sell_amount_raw / 10f64.powi(sell_decimals as i32);

    let (buy_amount_human, price, price_impact) = if buy_price > 0.0 {
        let rate = sell_price / buy_price;
        let buy_human = sell_amount_human * rate * 0.9995; // 0.05% fee
        let impact = 0.05 + (sell_amount_human * sell_price / 1_000_000.0) * 0.1;
        (buy_human, rate, impact.min(5.0))
    } else {
        (0.0, 0.0, 0.0)
    };

    let buy_decimals = token_decimals(&params.buy_token);
    let buy_amount_raw = buy_amount_human * 10f64.powi(buy_decimals as i32);

    let route = {
        let s = params.sell_token.to_uppercase();
        let b = params.buy_token.to_uppercase();
        if s == b {
            vec![s]
        } else if s == "USDC" || b == "USDC" || s == "USDT" || b == "USDT" {
            vec![s, b]
        } else {
            vec![s, "USDC".to_string(), b]
        }
    };

    // Split routing for large orders (> $10k).
    let usd_value = sell_amount_human * sell_price;
    let split_routes = if usd_value > 10_000.0 && route.len() >= 2 {
        let s = params.sell_token.to_uppercase();
        let b = params.buy_token.to_uppercase();
        let primary_pct = 70u32;
        let secondary_pct = 30u32;
        let primary_amount = buy_amount_raw * (primary_pct as f64 / 100.0);
        let secondary_amount = buy_amount_raw * (secondary_pct as f64 / 100.0);
        let primary_path = route.clone();
        let secondary_path = vec![s, "USDT".to_string(), b];
        Some(vec![
            SplitRoute {
                path: primary_path,
                percentage: primary_pct,
                buy_amount: format!("{:.0}", primary_amount),
            },
            SplitRoute {
                path: secondary_path,
                percentage: secondary_pct,
                buy_amount: format!("{:.0}", secondary_amount),
            },
        ])
    } else {
        None
    };

    Json(QuoteResponse {
        sell_token: params.sell_token,
        buy_token: params.buy_token,
        sell_amount: params.sell_amount,
        buy_amount: format!("{:.0}", buy_amount_raw),
        price: format!("{:.6}", price),
        price_impact: format!("{:.4}", price_impact),
        route,
        routes: split_routes,
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/v1/quote", get(get_quote))
}

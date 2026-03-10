//! Application router setup.

use std::sync::Arc;

use axum::http::{header, HeaderValue, Method};
use axum::Router;
use tower::limit::ConcurrencyLimitLayer;
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;

use ari_engine::state::EngineState;

use crate::db;
use crate::routes;
use crate::ws;

/// A stored intent record.
#[derive(Clone, serde::Serialize)]
pub struct StoredIntent {
    pub intent_id: String,
    pub sender: String,
    pub sell_token: String,
    pub buy_token: String,
    pub sell_amount: String,
    pub min_buy_amount: String,
    pub status: String,
    pub created_at: u64,
}

/// Shared application state passed to all handlers.
pub struct AppState {
    /// The matching engine state.
    pub engine: std::sync::Mutex<EngineState>,
    /// SQLite database connection.
    pub db: tokio::sync::Mutex<rusqlite::Connection>,
    /// Broadcast channel for WebSocket events.
    pub broadcast_tx: tokio::sync::broadcast::Sender<ws::BroadcastEvent>,
    /// Current number of active WebSocket connections.
    pub ws_connections: std::sync::atomic::AtomicUsize,
}

/// Maximum number of concurrent WebSocket connections.
pub const MAX_WS_CONNECTIONS: usize = 1000;

/// Builds the axum router with all routes and middleware.
pub fn build_router(engine: EngineState) -> Router {
    let conn = db::init_db("./ari-dex.db").expect("Failed to initialize SQLite database");

    let broadcast_tx = ws::create_broadcast();
    ws::spawn_price_ticker(broadcast_tx.clone());

    let state = Arc::new(AppState {
        engine: std::sync::Mutex::new(engine),
        db: tokio::sync::Mutex::new(conn),
        broadcast_tx,
        ws_connections: std::sync::atomic::AtomicUsize::new(0),
    });

    let cors = CorsLayer::new()
        .allow_origin([
            "http://localhost:3000".parse::<HeaderValue>().unwrap(),
            "https://dex-spec.fly.dev".parse::<HeaderValue>().unwrap(),
            "https://ari-dex-api.fly.dev".parse::<HeaderValue>().unwrap(),
        ])
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION]);

    // Serve frontend static files from ./frontend/dist (fallback)
    let serve_dir = ServeDir::new("frontend/dist")
        .append_index_html_on_directories(true);

    Router::new()
        .merge(routes::health::router())
        .merge(routes::intents::router())
        .merge(routes::quote::router())
        .merge(routes::pools::router())
        .merge(routes::tokens::router())
        .merge(routes::liquidity::router())
        .merge(routes::history::router())
        .merge(routes::social::router())
        .merge(routes::solvers::router())
        .merge(routes::rfq::router())
        .merge(routes::referral::router())
        .merge(routes::portfolio::router())
        .merge(routes::yield_agg::router())
        .merge(routes::positions::router())
        .merge(ws::router())
        .fallback_service(serve_dir)
        .layer(cors)
        .layer(ConcurrencyLimitLayer::new(100))
        .with_state(state)
}

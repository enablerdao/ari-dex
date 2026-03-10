//! Application router setup.

use std::collections::HashMap;
use std::sync::Arc;

use axum::Router;
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;

use ari_engine::state::EngineState;

use crate::routes;

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
    /// In-memory intent store.
    pub intents: std::sync::Mutex<HashMap<String, StoredIntent>>,
    /// Counter for generating intent IDs.
    pub intent_counter: std::sync::atomic::AtomicU64,
}

/// Builds the axum router with all routes and middleware.
pub fn build_router(engine: EngineState) -> Router {
    let state = Arc::new(AppState {
        engine: std::sync::Mutex::new(engine),
        intents: std::sync::Mutex::new(HashMap::new()),
        intent_counter: std::sync::atomic::AtomicU64::new(1),
    });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

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
        .fallback_service(serve_dir)
        .layer(cors)
        .with_state(state)
}

//! Application router setup.

use std::sync::Arc;

use axum::Router;
use tower_http::cors::{Any, CorsLayer};

use ari_engine::state::EngineState;

use crate::routes;

/// Shared application state passed to all handlers.
pub struct AppState {
    /// The matching engine state.
    pub engine: std::sync::Mutex<EngineState>,
}

/// Builds the axum router with all routes and middleware.
pub fn build_router(engine: EngineState) -> Router {
    let state = Arc::new(AppState {
        engine: std::sync::Mutex::new(engine),
    });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .merge(routes::health::router())
        .merge(routes::intents::router())
        .merge(routes::quote::router())
        .merge(routes::pools::router())
        .merge(routes::tokens::router())
        .merge(routes::liquidity::router())
        .merge(routes::history::router())
        .layer(cors)
        .with_state(state)
}

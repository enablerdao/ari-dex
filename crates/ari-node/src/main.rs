//! ARI DEX node binary.
//!
//! Starts the matching engine and HTTP gateway.

use ari_engine::state::EngineState;
use ari_gateway::app::build_router;
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    // Initialize tracing subscriber for structured logging.
    tracing_subscriber::fmt()
        .with_target(false)
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    info!("Starting ARI DEX node v{}", env!("CARGO_PKG_VERSION"));

    // Create the engine state.
    let engine = EngineState::new();
    info!("Engine state initialized");

    // Build the HTTP router.
    let app = build_router(engine);

    // Bind and serve.
    let addr = "0.0.0.0:3000";
    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind to address");

    axum::serve(listener, app)
        .await
        .expect("server error");
}

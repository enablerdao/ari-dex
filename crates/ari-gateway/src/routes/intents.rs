//! Intent submission and query endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::AppState;

#[derive(Deserialize)]
struct SubmitIntentRequest {
    /// Hex-encoded sender address.
    sender: String,
    /// Sell token symbol.
    sell_token: String,
    /// Buy token symbol.
    buy_token: String,
    /// Sell amount as a decimal string.
    sell_amount: String,
    /// Minimum buy amount as a decimal string.
    min_buy_amount: String,
}

#[derive(Serialize)]
struct SubmitIntentResponse {
    intent_id: String,
    status: String,
}

#[derive(Serialize)]
struct IntentResponse {
    intent_id: String,
    status: String,
}

async fn submit_intent(
    State(_state): State<Arc<AppState>>,
    Json(_body): Json<SubmitIntentRequest>,
) -> Json<SubmitIntentResponse> {
    // TODO: Parse request, create Intent, submit to engine
    Json(SubmitIntentResponse {
        intent_id: "0x0000000000000000000000000000000000000000000000000000000000000000"
            .to_string(),
        status: "pending".to_string(),
    })
}

async fn get_intent(
    State(_state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Json<IntentResponse> {
    // TODO: Look up intent by ID
    Json(IntentResponse {
        intent_id: id,
        status: "pending".to_string(),
    })
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/intents", post(submit_intent))
        .route("/v1/intents/{id}", get(get_intent))
}

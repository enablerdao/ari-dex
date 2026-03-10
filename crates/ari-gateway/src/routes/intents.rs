//! Intent submission and query endpoints.

use std::sync::Arc;
use std::sync::atomic::Ordering;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::{AppState, StoredIntent};

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

async fn submit_intent(
    State(state): State<Arc<AppState>>,
    Json(body): Json<SubmitIntentRequest>,
) -> (StatusCode, Json<SubmitIntentResponse>) {
    let counter = state.intent_counter.fetch_add(1, Ordering::SeqCst);
    let intent_id = format!("0x{:064x}", counter);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let stored = StoredIntent {
        intent_id: intent_id.clone(),
        sender: body.sender,
        sell_token: body.sell_token,
        buy_token: body.buy_token,
        sell_amount: body.sell_amount,
        min_buy_amount: body.min_buy_amount,
        status: "pending".to_string(),
        created_at: now,
    };

    state
        .intents
        .lock()
        .unwrap()
        .insert(intent_id.clone(), stored);

    (
        StatusCode::CREATED,
        Json(SubmitIntentResponse {
            intent_id,
            status: "pending".to_string(),
        }),
    )
}

async fn get_intent(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<StoredIntent>, StatusCode> {
    let intents = state.intents.lock().unwrap();
    match intents.get(&id) {
        Some(intent) => Ok(Json(intent.clone())),
        None => Err(StatusCode::NOT_FOUND),
    }
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/intents", post(submit_intent))
        .route("/v1/intents/:id", get(get_intent))
}

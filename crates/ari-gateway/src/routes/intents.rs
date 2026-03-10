//! Intent submission and query endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::{AppState, StoredIntent};
use crate::db;
use crate::ws;

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
    /// Optional referral code for tracking.
    referral_code: Option<String>,
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
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Generate a unique ID using timestamp + random suffix
    let intent_id = format!(
        "0x{:016x}{:048x}",
        now,
        rand::random::<u64>()
    );

    let referral_code = body.referral_code;

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

    {
        let conn = state.db.lock().unwrap();
        if let Err(e) = db::insert_intent(&conn, &stored, referral_code.as_deref()) {
            tracing::error!("Failed to insert intent: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(SubmitIntentResponse {
                    intent_id: String::new(),
                    status: "error".to_string(),
                }),
            );
        }
        // Track referral if a code was provided.
        if let Some(ref code) = referral_code {
            crate::routes::referral::track_referral(&conn, code, &stored.sell_amount);
        }
    }

    // Broadcast to WebSocket subscribers
    ws::broadcast_intent(&state.broadcast_tx, &stored);

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
    let conn = state.db.lock().unwrap();
    match db::get_intent(&conn, &id) {
        Ok(Some(intent)) => Ok(Json(intent)),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(e) => {
            tracing::error!("Failed to get intent: {e}");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/intents", post(submit_intent))
        .route("/v1/intents/:id", get(get_intent))
}

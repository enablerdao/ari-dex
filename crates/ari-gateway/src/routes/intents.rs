//! Intent submission and query endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;

use crate::app::{AppState, StoredIntent};
use crate::db;
use crate::validation;
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

async fn submit_intent(
    State(state): State<Arc<AppState>>,
    Json(body): Json<SubmitIntentRequest>,
) -> impl IntoResponse {
    // Validate amounts before processing.
    if let Err(e) = validation::validate_amount(&body.sell_amount) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("invalid sell_amount: {e}")})),
        )
            .into_response();
    }
    if let Err(e) = validation::validate_amount(&body.min_buy_amount) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("invalid min_buy_amount: {e}")})),
        )
            .into_response();
    }

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
        let conn = state.db.lock().await;
        if let Err(e) = db::insert_intent(&conn, &stored, referral_code.as_deref()) {
            tracing::error!("Failed to insert intent: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "internal error"})),
            )
                .into_response();
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
        Json(serde_json::json!({
            "intent_id": intent_id,
            "status": "pending",
        })),
    )
        .into_response()
}

async fn get_intent(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    let conn = state.db.lock().await;
    match db::get_intent(&conn, &id) {
        Ok(Some(intent)) => Json(serde_json::to_value(intent).unwrap()).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(e) => {
            tracing::error!("Failed to get intent: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "internal error"})),
            )
                .into_response()
        }
    }
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/intents", post(submit_intent))
        .route("/v1/intents/:id", get(get_intent))
}

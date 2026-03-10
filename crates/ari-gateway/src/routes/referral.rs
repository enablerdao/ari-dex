//! Referral tracking system endpoints.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use crate::app::AppState;

// ---------------------------------------------------------------------------
// Request / response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct RegisterReferralRequest {
    pub owner: String,
}

#[derive(Serialize)]
pub struct RegisterReferralResponse {
    pub code: String,
    pub owner: String,
}

#[derive(Serialize)]
pub struct ReferralStats {
    pub code: String,
    pub owner: String,
    pub referred_count: i64,
    pub total_volume: String,
    pub created_at: u64,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Generate a short, human-friendly referral code.
fn gen_referral_code() -> String {
    let r: u64 = rand::random();
    format!("REF-{}", &format!("{:X}", r)[..8])
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// POST /v1/referral/register — register a new referral code.
async fn register_referral(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RegisterReferralRequest>,
) -> Result<(StatusCode, Json<RegisterReferralResponse>), StatusCode> {
    let code = gen_referral_code();
    let now = now_secs();

    let conn = state.db.lock().unwrap();
    conn.execute(
        "INSERT INTO referrals (code, owner, referred_count, total_volume, created_at) VALUES (?1, ?2, 0, '0', ?3)",
        rusqlite::params![code, body.owner, now],
    )
    .map_err(|e| {
        tracing::error!("Failed to register referral: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok((
        StatusCode::CREATED,
        Json(RegisterReferralResponse {
            code,
            owner: body.owner,
        }),
    ))
}

/// GET /v1/referral/:code — get referral stats.
async fn get_referral_stats(
    State(state): State<Arc<AppState>>,
    Path(code): Path<String>,
) -> Result<Json<ReferralStats>, StatusCode> {
    let conn = state.db.lock().unwrap();

    let stats = conn
        .query_row(
            "SELECT code, owner, referred_count, total_volume, created_at FROM referrals WHERE code = ?1",
            rusqlite::params![code],
            |row| {
                Ok(ReferralStats {
                    code: row.get(0)?,
                    owner: row.get(1)?,
                    referred_count: row.get(2)?,
                    total_volume: row.get(3)?,
                    created_at: row.get(4)?,
                })
            },
        )
        .map_err(|_| StatusCode::NOT_FOUND)?;

    Ok(Json(stats))
}

/// Track a referral code when an intent is submitted.
/// Call this from the intents handler when a `referral_code` is present.
pub fn track_referral(conn: &rusqlite::Connection, referral_code: &str, sell_amount: &str) {
    let volume: f64 = sell_amount.parse().unwrap_or(0.0);

    let res = conn.execute(
        "UPDATE referrals SET referred_count = referred_count + 1, total_volume = CAST((CAST(total_volume AS REAL) + ?1) AS TEXT) WHERE code = ?2",
        rusqlite::params![volume, referral_code],
    );

    if let Err(e) = res {
        tracing::warn!("Failed to track referral {referral_code}: {e}");
    }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/referral/register", post(register_referral))
        .route("/v1/referral/:code", get(get_referral_stats))
}

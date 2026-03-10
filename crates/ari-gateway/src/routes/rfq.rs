//! RFQ (Request for Quote) system endpoints.

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
pub struct CreateRfqRequest {
    pub sell_token: String,
    pub buy_token: String,
    pub sell_amount: String,
    pub requester: String,
}

#[derive(Serialize)]
pub struct CreateRfqResponse {
    pub rfq_id: String,
    pub status: String,
    pub expires_at: u64,
}

#[derive(Serialize)]
pub struct RfqDetail {
    pub id: String,
    pub requester: String,
    pub sell_token: String,
    pub buy_token: String,
    pub sell_amount: String,
    pub status: String,
    pub best_quote: Option<String>,
    pub best_quoter: Option<String>,
    pub created_at: u64,
    pub expires_at: u64,
    pub quotes: Vec<RfqQuote>,
}

#[derive(Serialize, Clone)]
pub struct RfqQuote {
    pub id: String,
    pub rfq_id: String,
    pub quoter: String,
    pub buy_amount: String,
    pub created_at: u64,
}

#[derive(Deserialize)]
pub struct SubmitQuoteRequest {
    pub quoter: String,
    pub buy_amount: String,
}

#[derive(Serialize)]
pub struct SubmitQuoteResponse {
    pub quote_id: String,
    pub is_best: bool,
}

#[derive(Serialize)]
pub struct AcceptQuoteResponse {
    pub rfq_id: String,
    pub status: String,
    pub accepted_quoter: String,
    pub accepted_amount: String,
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

fn gen_id(prefix: &str) -> String {
    format!("{}-{:016x}{:016x}", prefix, now_secs(), rand::random::<u64>())
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// POST /v1/rfq — create a new RFQ.
async fn create_rfq(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CreateRfqRequest>,
) -> (StatusCode, Json<CreateRfqResponse>) {
    let now = now_secs();
    let expires = now + 300; // 5 minutes
    let rfq_id = gen_id("rfq");

    let conn = state.db.lock().unwrap();
    let res = conn.execute(
        "INSERT INTO rfqs (id, requester, sell_token, buy_token, sell_amount, status, created_at, expires_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 'open', ?6, ?7)",
        rusqlite::params![rfq_id, body.requester, body.sell_token, body.buy_token, body.sell_amount, now, expires],
    );

    if let Err(e) = res {
        tracing::error!("Failed to create RFQ: {e}");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(CreateRfqResponse {
                rfq_id: String::new(),
                status: "error".into(),
                expires_at: 0,
            }),
        );
    }

    (
        StatusCode::CREATED,
        Json(CreateRfqResponse {
            rfq_id,
            status: "open".into(),
            expires_at: expires,
        }),
    )
}

/// GET /v1/rfq/:id — get RFQ status and quotes.
async fn get_rfq(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<RfqDetail>, StatusCode> {
    let conn = state.db.lock().unwrap();

    let rfq = conn
        .query_row(
            "SELECT id, requester, sell_token, buy_token, sell_amount, status, best_quote, best_quoter, created_at, expires_at
             FROM rfqs WHERE id = ?1",
            rusqlite::params![id],
            |row| {
                Ok(RfqDetail {
                    id: row.get(0)?,
                    requester: row.get(1)?,
                    sell_token: row.get(2)?,
                    buy_token: row.get(3)?,
                    sell_amount: row.get(4)?,
                    status: row.get(5)?,
                    best_quote: row.get(6)?,
                    best_quoter: row.get(7)?,
                    created_at: row.get(8)?,
                    expires_at: row.get(9)?,
                    quotes: Vec::new(),
                })
            },
        )
        .map_err(|_| StatusCode::NOT_FOUND)?;

    // Fetch associated quotes.
    let mut stmt = conn
        .prepare(
            "SELECT id, rfq_id, quoter, buy_amount, created_at FROM rfq_quotes WHERE rfq_id = ?1 ORDER BY buy_amount DESC",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let quotes: Vec<RfqQuote> = stmt
        .query_map(rusqlite::params![id], |row| {
            Ok(RfqQuote {
                id: row.get(0)?,
                rfq_id: row.get(1)?,
                quoter: row.get(2)?,
                buy_amount: row.get(3)?,
                created_at: row.get(4)?,
            })
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();

    let detail = RfqDetail { quotes, ..rfq };
    Ok(Json(detail))
}

/// POST /v1/rfq/:id/quote — market maker submits a quote.
async fn submit_quote(
    State(state): State<Arc<AppState>>,
    Path(rfq_id): Path<String>,
    Json(body): Json<SubmitQuoteRequest>,
) -> Result<(StatusCode, Json<SubmitQuoteResponse>), StatusCode> {
    let now = now_secs();
    let quote_id = gen_id("quote");

    let conn = state.db.lock().unwrap();

    // Verify RFQ exists and is open.
    let status: String = conn
        .query_row(
            "SELECT status FROM rfqs WHERE id = ?1",
            rusqlite::params![rfq_id],
            |row| row.get(0),
        )
        .map_err(|_| StatusCode::NOT_FOUND)?;

    if status != "open" {
        return Err(StatusCode::CONFLICT);
    }

    conn.execute(
        "INSERT INTO rfq_quotes (id, rfq_id, quoter, buy_amount, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![quote_id, rfq_id, body.quoter, body.buy_amount, now],
    )
    .map_err(|e| {
        tracing::error!("Failed to insert quote: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // Check if this is the new best quote (highest buy_amount).
    let current_best: Option<String> = conn
        .query_row(
            "SELECT best_quote FROM rfqs WHERE id = ?1",
            rusqlite::params![rfq_id],
            |row| row.get(0),
        )
        .unwrap_or(None);

    let is_best = match current_best {
        None => true,
        Some(ref prev) => {
            let prev_val: f64 = prev.parse().unwrap_or(0.0);
            let new_val: f64 = body.buy_amount.parse().unwrap_or(0.0);
            new_val > prev_val
        }
    };

    if is_best {
        conn.execute(
            "UPDATE rfqs SET best_quote = ?1, best_quoter = ?2 WHERE id = ?3",
            rusqlite::params![body.buy_amount, body.quoter, rfq_id],
        )
        .map_err(|e| {
            tracing::error!("Failed to update best quote: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    }

    Ok((
        StatusCode::CREATED,
        Json(SubmitQuoteResponse {
            quote_id,
            is_best,
        }),
    ))
}

/// POST /v1/rfq/:id/accept — requester accepts the best quote.
async fn accept_quote(
    State(state): State<Arc<AppState>>,
    Path(rfq_id): Path<String>,
) -> Result<Json<AcceptQuoteResponse>, StatusCode> {
    let conn = state.db.lock().unwrap();

    let (status, best_quote, best_quoter): (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT status, best_quote, best_quoter FROM rfqs WHERE id = ?1",
            rusqlite::params![rfq_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|_| StatusCode::NOT_FOUND)?;

    if status != "open" {
        return Err(StatusCode::CONFLICT);
    }

    let quoter = best_quoter.ok_or(StatusCode::BAD_REQUEST)?;
    let amount = best_quote.ok_or(StatusCode::BAD_REQUEST)?;

    conn.execute(
        "UPDATE rfqs SET status = 'accepted' WHERE id = ?1",
        rusqlite::params![rfq_id],
    )
    .map_err(|e| {
        tracing::error!("Failed to accept RFQ: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(AcceptQuoteResponse {
        rfq_id,
        status: "accepted".into(),
        accepted_quoter: quoter,
        accepted_amount: amount,
    }))
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/rfq", post(create_rfq))
        .route("/v1/rfq/:id", get(get_rfq))
        .route("/v1/rfq/:id/quote", post(submit_quote))
        .route("/v1/rfq/:id/accept", post(accept_quote))
}

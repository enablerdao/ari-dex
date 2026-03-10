//! Solver marketplace endpoints: list, detail, leaderboard, register, history.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::app::AppState;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct Solver {
    id: String,
    address: String,
    name: String,
    endpoint: String,
    fill_rate: f64,
    avg_improvement: f64,
    total_volume: String,
    total_fills: i64,
    score: f64,
    active: bool,
    created_at: i64,
}

#[derive(Serialize)]
struct SolversResponse {
    solvers: Vec<Solver>,
}

#[derive(Deserialize)]
struct RegisterRequest {
    address: String,
    name: String,
    endpoint: String,
}

#[derive(Serialize)]
struct FillRecord {
    intent_id: String,
    price_improvement: f64,
    amount: String,
    timestamp: i64,
}

#[derive(Serialize)]
struct HistoryResponse {
    fills: Vec<FillRecord>,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn row_to_solver(row: &rusqlite::Row<'_>) -> rusqlite::Result<Solver> {
    Ok(Solver {
        id: row.get(0)?,
        address: row.get(1)?,
        name: row.get(2)?,
        endpoint: row.get(3)?,
        fill_rate: row.get(4)?,
        avg_improvement: row.get(5)?,
        total_volume: row.get(6)?,
        total_fills: row.get(7)?,
        score: row.get(8)?,
        active: {
            let v: i64 = row.get(9)?;
            v != 0
        },
        created_at: row.get(10)?,
    })
}

const SOLVER_COLS: &str =
    "id, address, name, endpoint, fill_rate, avg_improvement, total_volume, total_fills, score, active, created_at";

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn list_solvers(State(state): State<Arc<AppState>>) -> Json<SolversResponse> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare(&format!(
            "SELECT {} FROM solvers WHERE active = 1 ORDER BY score DESC",
            SOLVER_COLS
        ))
        .unwrap();
    let solvers = stmt
        .query_map([], row_to_solver)
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();
    Json(SolversResponse { solvers })
}

async fn solver_detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Json<serde_json::Value> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare(&format!(
            "SELECT {} FROM solvers WHERE id = ?1",
            SOLVER_COLS
        ))
        .unwrap();
    let solver = stmt
        .query_map(params![id], row_to_solver)
        .unwrap()
        .filter_map(|r| r.ok())
        .next();
    match solver {
        Some(s) => Json(serde_json::to_value(s).unwrap()),
        None => Json(serde_json::json!({"error": "solver not found"})),
    }
}

async fn solver_leaderboard(State(state): State<Arc<AppState>>) -> Json<SolversResponse> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare(&format!(
            "SELECT {} FROM solvers ORDER BY score DESC",
            SOLVER_COLS
        ))
        .unwrap();
    let solvers = stmt
        .query_map([], row_to_solver)
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();
    Json(SolversResponse { solvers })
}

async fn register_solver(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RegisterRequest>,
) -> Json<Solver> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    let id = format!("solver_{}", now);
    let db = state.db.lock().unwrap();
    db.execute(
        "INSERT INTO solvers (id, address, name, endpoint, fill_rate, avg_improvement, total_volume, total_fills, score, active, created_at)
         VALUES (?1, ?2, ?3, ?4, 0.0, 0.0, '0', 0, 50.0, 1, ?5)",
        params![id, body.address, body.name, body.endpoint, now],
    )
    .unwrap();
    Json(Solver {
        id,
        address: body.address,
        name: body.name,
        endpoint: body.endpoint,
        fill_rate: 0.0,
        avg_improvement: 0.0,
        total_volume: "0".to_string(),
        total_fills: 0,
        score: 50.0,
        active: true,
        created_at: now,
    })
}

async fn solver_history(
    State(_state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Json<HistoryResponse> {
    // Mock fill history for the solver
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    let fills = (0..5)
        .map(|i| FillRecord {
            intent_id: format!("intent_{}_{}", id, i),
            price_improvement: 0.15 + (i as f64) * 0.05,
            amount: format!("{}", 1_000_000_000u64 * (i + 1)),
            timestamp: now - (i as i64) * 3600,
        })
        .collect();
    Json(HistoryResponse { fills })
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/solvers", get(list_solvers))
        .route("/v1/solvers/leaderboard", get(solver_leaderboard))
        .route("/v1/solvers/register", post(register_solver))
        .route("/v1/solvers/{id}", get(solver_detail))
        .route("/v1/solvers/{id}/history", get(solver_history))
}

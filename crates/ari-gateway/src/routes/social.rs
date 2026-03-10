//! Social trading endpoints: leaderboard, follow/unfollow, copy-trade.

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
struct TraderStats {
    address: String,
    total_pnl: String,
    win_rate: f64,
    trade_count: i64,
    volume: String,
}

#[derive(Serialize)]
struct LeaderboardResponse {
    traders: Vec<TraderStats>,
}

#[derive(Deserialize)]
struct FollowRequest {
    follower: String,
    trader: String,
}

#[derive(Serialize)]
struct FollowEntry {
    trader: String,
    created_at: i64,
}

#[derive(Serialize)]
struct FollowingResponse {
    following: Vec<FollowEntry>,
}

#[derive(Deserialize)]
struct CopyTradeRequest {
    copier: String,
    trader: String,
    max_amount: String,
}

#[derive(Serialize)]
struct CopyTrade {
    id: String,
    copier: String,
    trader: String,
    max_amount: String,
    active: bool,
    created_at: i64,
}

#[derive(Serialize)]
struct CopyTradesResponse {
    copy_trades: Vec<CopyTrade>,
}

#[derive(Serialize)]
struct StatusResponse {
    status: &'static str,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn leaderboard(State(state): State<Arc<AppState>>) -> Json<LeaderboardResponse> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare(
            "SELECT address, total_pnl, win_rate, trade_count, volume
             FROM trader_stats ORDER BY CAST(total_pnl AS REAL) DESC LIMIT 10",
        )
        .unwrap();
    let traders = stmt
        .query_map([], |row| {
            Ok(TraderStats {
                address: row.get(0)?,
                total_pnl: row.get(1)?,
                win_rate: row.get(2)?,
                trade_count: row.get(3)?,
                volume: row.get(4)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();
    Json(LeaderboardResponse { traders })
}

async fn follow(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FollowRequest>,
) -> Json<StatusResponse> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    let db = state.db.lock().unwrap();
    db.execute(
        "INSERT OR IGNORE INTO follows (follower, trader, created_at) VALUES (?1, ?2, ?3)",
        params![body.follower, body.trader, now],
    )
    .unwrap();
    Json(StatusResponse { status: "followed" })
}

async fn unfollow(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FollowRequest>,
) -> Json<StatusResponse> {
    let db = state.db.lock().unwrap();
    db.execute(
        "DELETE FROM follows WHERE follower = ?1 AND trader = ?2",
        params![body.follower, body.trader],
    )
    .unwrap();
    Json(StatusResponse {
        status: "unfollowed",
    })
}

async fn following(
    State(state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<FollowingResponse> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare("SELECT trader, created_at FROM follows WHERE follower = ?1 ORDER BY created_at DESC")
        .unwrap();
    let following = stmt
        .query_map(params![address], |row| {
            Ok(FollowEntry {
                trader: row.get(0)?,
                created_at: row.get(1)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();
    Json(FollowingResponse { following })
}

async fn create_copy_trade(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CopyTradeRequest>,
) -> Json<CopyTrade> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    let id = format!("ct_{}", now);
    let db = state.db.lock().unwrap();
    db.execute(
        "INSERT INTO copy_trades (id, copier, trader, max_amount, active, created_at)
         VALUES (?1, ?2, ?3, ?4, 1, ?5)",
        params![id, body.copier, body.trader, body.max_amount, now],
    )
    .unwrap();
    Json(CopyTrade {
        id,
        copier: body.copier,
        trader: body.trader,
        max_amount: body.max_amount,
        active: true,
        created_at: now,
    })
}

async fn list_copy_trades(
    State(state): State<Arc<AppState>>,
    Path(address): Path<String>,
) -> Json<CopyTradesResponse> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare(
            "SELECT id, copier, trader, max_amount, active, created_at
             FROM copy_trades WHERE copier = ?1 AND active = 1 ORDER BY created_at DESC",
        )
        .unwrap();
    let copy_trades = stmt
        .query_map(params![address], |row| {
            Ok(CopyTrade {
                id: row.get(0)?,
                copier: row.get(1)?,
                trader: row.get(2)?,
                max_amount: row.get(3)?,
                active: {
                    let v: i64 = row.get(4)?;
                    v != 0
                },
                created_at: row.get(5)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();
    Json(CopyTradesResponse { copy_trades })
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/v1/social/leaderboard", get(leaderboard))
        .route("/v1/social/follow", post(follow).delete(unfollow))
        .route("/v1/social/following/{address}", get(following))
        .route("/v1/social/copy-trade", post(create_copy_trade))
        .route("/v1/social/copy-trades/{address}", get(list_copy_trades))
}

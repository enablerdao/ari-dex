//! SQLite persistence layer for intents.

use rusqlite::{params, Connection, Result};

use crate::app::StoredIntent;

/// Initialize the database, creating tables if they don't exist.
pub fn init_db(path: &str) -> Result<Connection> {
    let conn = Connection::open(path)?;
    conn.execute_batch("PRAGMA journal_mode = WAL;")?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS intents (
            id          TEXT PRIMARY KEY,
            sender      TEXT NOT NULL,
            sell_token  TEXT NOT NULL,
            buy_token   TEXT NOT NULL,
            sell_amount TEXT NOT NULL,
            min_buy_amount TEXT NOT NULL,
            status      TEXT NOT NULL DEFAULT 'pending',
            referral_code TEXT,
            created_at  INTEGER NOT NULL
        );",
    )?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS rfqs (
            id TEXT PRIMARY KEY,
            requester TEXT NOT NULL,
            sell_token TEXT NOT NULL,
            buy_token TEXT NOT NULL,
            sell_amount TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'open',
            best_quote TEXT,
            best_quoter TEXT,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS rfq_quotes (
            id TEXT PRIMARY KEY,
            rfq_id TEXT NOT NULL,
            quoter TEXT NOT NULL,
            buy_amount TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS referrals (
            code TEXT PRIMARY KEY,
            owner TEXT NOT NULL,
            referred_count INTEGER DEFAULT 0,
            total_volume TEXT DEFAULT '0',
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS yield_positions (
            id TEXT PRIMARY KEY,
            owner TEXT NOT NULL,
            strategy_id TEXT NOT NULL,
            token TEXT NOT NULL,
            amount TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );",
    )?;

    // Social trading tables
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS follows (
            follower TEXT NOT NULL,
            trader TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (follower, trader)
        );
        CREATE TABLE IF NOT EXISTS copy_trades (
            id TEXT PRIMARY KEY,
            copier TEXT NOT NULL,
            trader TEXT NOT NULL,
            max_amount TEXT NOT NULL,
            active INTEGER DEFAULT 1,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS trader_stats (
            address TEXT PRIMARY KEY,
            total_pnl TEXT DEFAULT '0',
            win_rate REAL DEFAULT 0.0,
            trade_count INTEGER DEFAULT 0,
            volume TEXT DEFAULT '0'
        );",
    )?;

    // Seed mock trader stats
    let count: i64 = conn.query_row("SELECT COUNT(*) FROM trader_stats", [], |r| r.get(0))?;
    if count == 0 {
        let mock_traders: &[(&str, &str, f64, i64, &str)] = &[
            ("0xA1b2C3d4E5f6789012345678901234567890abCD", "125000000000", 0.72, 342, "89000000000000"),
            ("0xB2c3D4e5F67890123456789012345678901BcDeF", "98000000000", 0.68, 287, "67000000000000"),
            ("0xC3d4E5f678901234567890123456789012CdEfAb", "76000000000", 0.65, 198, "54000000000000"),
            ("0xD4e5F6789012345678901234567890123DeFaBcD", "54000000000", 0.61, 156, "41000000000000"),
            ("0xE5f67890123456789012345678901234EfAbCdEf", "32000000000", 0.58, 124, "29000000000000"),
            ("0xF678901234567890123456789012345FaBcDeFaB", "21000000000", 0.55, 98, "18000000000000"),
            ("0x1789012345678901234567890123456AbCdEfAbC", "15000000000", 0.52, 76, "12000000000000"),
            ("0x2890123456789012345678901234567BcDeFaBcD", "8000000000", 0.49, 54, "7000000000000"),
            ("0x3901234567890123456789012345678CdEfAbCdE", "-5000000000", 0.42, 43, "5000000000000"),
            ("0x4012345678901234567890123456789DeFaBcDeF", "-12000000000", 0.38, 31, "3000000000000"),
        ];
        for (addr, pnl, wr, tc, vol) in mock_traders {
            conn.execute(
                "INSERT INTO trader_stats (address, total_pnl, win_rate, trade_count, volume)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![addr, pnl, wr, tc, vol],
            )?;
        }
    }

    // Solver marketplace table
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS solvers (
            id TEXT PRIMARY KEY,
            address TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            fill_rate REAL DEFAULT 0.0,
            avg_improvement REAL DEFAULT 0.0,
            total_volume TEXT DEFAULT '0',
            total_fills INTEGER DEFAULT 0,
            score REAL DEFAULT 50.0,
            active INTEGER DEFAULT 1,
            created_at INTEGER NOT NULL
        );",
    )?;

    // Seed mock solvers
    let solver_count: i64 = conn.query_row("SELECT COUNT(*) FROM solvers", [], |r| r.get(0))?;
    if solver_count == 0 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;
        let mock_solvers: &[(&str, &str, &str, &str, f64, f64, &str, i64, f64)] = &[
            ("solver_1", "0xS01ver1111111111111111111111111111111111", "Wintermute", "https://solver.wintermute.com/v1", 0.94, 0.12, "4500000000000000", 12840, 92.5),
            ("solver_2", "0xS01ver2222222222222222222222222222222222", "Flashbots Protect", "https://protect.flashbots.net/solver", 0.91, 0.18, "3200000000000000", 9650, 88.3),
            ("solver_3", "0xS01ver3333333333333333333333333333333333", "ParaSwap Delta", "https://delta.paraswap.io/solve", 0.87, 0.09, "2100000000000000", 7320, 79.1),
            ("solver_4", "0xS01ver4444444444444444444444444444444444", "1inch Fusion", "https://fusion.1inch.io/solver", 0.85, 0.15, "1800000000000000", 5410, 75.6),
            ("solver_5", "0xS01ver5555555555555555555555555555555555", "CoW Protocol", "https://solver.cow.fi/v1", 0.82, 0.21, "980000000000000", 3200, 71.2),
        ];
        for (id, addr, name, endpoint, fr, ai, vol, fills, score) in mock_solvers {
            conn.execute(
                "INSERT INTO solvers (id, address, name, endpoint, fill_rate, avg_improvement, total_volume, total_fills, score, active, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10)",
                params![id, addr, name, endpoint, fr, ai, vol, fills, score, now],
            )?;
        }
    }

    Ok(conn)
}

/// Insert a new intent into the database.
pub fn insert_intent(conn: &Connection, intent: &StoredIntent, referral_code: Option<&str>) -> Result<()> {
    conn.execute(
        "INSERT INTO intents (id, sender, sell_token, buy_token, sell_amount, min_buy_amount, status, referral_code, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![
            intent.intent_id,
            intent.sender,
            intent.sell_token,
            intent.buy_token,
            intent.sell_amount,
            intent.min_buy_amount,
            intent.status,
            referral_code,
            intent.created_at,
        ],
    )?;
    Ok(())
}

/// Get a single intent by ID.
pub fn get_intent(conn: &Connection, id: &str) -> Result<Option<StoredIntent>> {
    let mut stmt = conn.prepare(
        "SELECT id, sender, sell_token, buy_token, sell_amount, min_buy_amount, status, created_at
         FROM intents WHERE id = ?1",
    )?;
    let mut rows = stmt.query_map(params![id], row_to_intent)?;
    match rows.next() {
        Some(row) => Ok(Some(row?)),
        None => Ok(None),
    }
}

/// List all intents, ordered by creation time descending.
pub fn list_intents(conn: &Connection, limit: usize) -> Result<Vec<StoredIntent>> {
    let mut stmt = conn.prepare(
        "SELECT id, sender, sell_token, buy_token, sell_amount, min_buy_amount, status, created_at
         FROM intents ORDER BY created_at DESC LIMIT ?1",
    )?;
    let rows = stmt.query_map(params![limit as i64], row_to_intent)?;
    rows.collect()
}

/// Update the status of an intent.
pub fn update_intent_status(conn: &Connection, id: &str, status: &str) -> Result<bool> {
    let changed = conn.execute(
        "UPDATE intents SET status = ?1 WHERE id = ?2",
        params![status, id],
    )?;
    Ok(changed > 0)
}

/// List intents for a specific sender address, optionally filtered by status.
pub fn list_intents_by_sender(
    conn: &Connection,
    sender: &str,
    status_filter: Option<&str>,
) -> Result<Vec<StoredIntent>> {
    match status_filter {
        Some(status) => {
            let mut stmt = conn.prepare(
                "SELECT id, sender, sell_token, buy_token, sell_amount, min_buy_amount, status, created_at
                 FROM intents WHERE sender = ?1 AND status = ?2 ORDER BY created_at DESC",
            )?;
            let rows = stmt.query_map(params![sender, status], row_to_intent)?;
            rows.collect()
        }
        None => {
            let mut stmt = conn.prepare(
                "SELECT id, sender, sell_token, buy_token, sell_amount, min_buy_amount, status, created_at
                 FROM intents WHERE sender = ?1 ORDER BY created_at DESC",
            )?;
            let rows = stmt.query_map(params![sender], row_to_intent)?;
            rows.collect()
        }
    }
}

// ---------------------------------------------------------------------------
// Yield positions
// ---------------------------------------------------------------------------

/// Insert a new yield position.
pub fn insert_yield_position(
    conn: &Connection,
    id: &str,
    owner: &str,
    strategy_id: &str,
    token: &str,
    amount: &str,
    created_at: u64,
) -> Result<()> {
    conn.execute(
        "INSERT INTO yield_positions (id, owner, strategy_id, token, amount, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![id, owner, strategy_id, token, amount, created_at],
    )?;
    Ok(())
}

/// List yield positions for a given owner.
pub fn list_yield_positions(
    conn: &Connection,
    owner: &str,
) -> Result<Vec<(String, String, String, String, String, u64)>> {
    let mut stmt = conn.prepare(
        "SELECT id, owner, strategy_id, token, amount, created_at
         FROM yield_positions WHERE owner = ?1 ORDER BY created_at DESC",
    )?;
    let rows = stmt.query_map(params![owner], |row| {
        Ok((
            row.get(0)?,
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
            row.get(4)?,
            row.get(5)?,
        ))
    })?;
    rows.collect()
}

fn row_to_intent(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredIntent> {
    Ok(StoredIntent {
        intent_id: row.get(0)?,
        sender: row.get(1)?,
        sell_token: row.get(2)?,
        buy_token: row.get(3)?,
        sell_amount: row.get(4)?,
        min_buy_amount: row.get(5)?,
        status: row.get(6)?,
        created_at: row.get(7)?,
    })
}

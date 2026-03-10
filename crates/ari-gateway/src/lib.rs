//! ARI DEX HTTP/WebSocket gateway.
//!
//! Provides the REST API and WebSocket endpoints for interacting
//! with the ARI decentralized exchange.

pub mod app;
pub mod db;
pub mod middleware;
pub mod routes;
pub mod validation;
pub mod ws;

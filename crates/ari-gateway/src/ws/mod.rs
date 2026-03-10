//! WebSocket support for real-time market data streaming.
//!
//! Supports two subscription channels:
//! - `prices`: Mock price updates every 5 seconds
//! - `intents`: Real-time intent submission notifications

use std::sync::atomic::Ordering;
use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use futures::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

use crate::app::{AppState, MAX_WS_CONNECTIONS};

/// Message sent by clients to subscribe to channels.
#[derive(Deserialize)]
struct SubscribeMessage {
    subscribe: String,
}

/// A price update broadcast message.
#[derive(Clone, Serialize)]
pub struct PriceUpdate {
    pub channel: &'static str,
    pub pair: String,
    pub price: f64,
    pub timestamp: u64,
}

/// An intent broadcast message.
#[derive(Clone, Serialize)]
pub struct IntentUpdate {
    pub channel: &'static str,
    pub intent_id: String,
    pub sender: String,
    pub sell_token: String,
    pub buy_token: String,
    pub sell_amount: String,
    pub status: String,
}

/// Broadcast event sent over the channel.
#[derive(Clone)]
pub enum BroadcastEvent {
    Price(PriceUpdate),
    Intent(IntentUpdate),
}

/// Create a broadcast channel for WebSocket events.
pub fn create_broadcast() -> broadcast::Sender<BroadcastEvent> {
    let (tx, _) = broadcast::channel(256);
    tx
}

/// Spawn the background price ticker that sends mock price updates.
pub fn spawn_price_ticker(tx: broadcast::Sender<BroadcastEvent>) {
    tokio::spawn(async move {
        let mut eth_price: f64 = 3500.0;
        let mut btc_price: f64 = 65000.0;

        loop {
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;

            // Small random walk using simple LCG to avoid non-Send ThreadRng
            let seed = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .subsec_nanos();
            let frac = (seed as f64) / (u32::MAX as f64); // 0.0..1.0
            eth_price += (frac - 0.5) * 100.0;
            btc_price += (frac - 0.5) * 1000.0;

            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();

            let _ = tx.send(BroadcastEvent::Price(PriceUpdate {
                channel: "prices",
                pair: "ETH/USDC".to_string(),
                price: (eth_price * 100.0).round() / 100.0,
                timestamp: now,
            }));

            let _ = tx.send(BroadcastEvent::Price(PriceUpdate {
                channel: "prices",
                pair: "BTC/USDC".to_string(),
                price: (btc_price * 100.0).round() / 100.0,
                timestamp: now,
            }));
        }
    });
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    // Check connection limit before upgrading.
    let current = state.ws_connections.load(Ordering::Relaxed);
    if current >= MAX_WS_CONNECTIONS {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    }

    ws.on_upgrade(move |socket| handle_socket(socket, state))
        .into_response()
}

async fn handle_socket(socket: WebSocket, state: Arc<AppState>) {
    // Increment connection counter.
    state.ws_connections.fetch_add(1, Ordering::Relaxed);

    let (mut ws_sender, mut ws_receiver) = socket.split();

    let mut subscribed_prices = false;
    let mut subscribed_intents = false;

    let mut broadcast_rx = state.broadcast_tx.subscribe();

    // Use a channel to send messages to the writer task
    let (msg_tx, mut msg_rx) = tokio::sync::mpsc::channel::<String>(64);

    // Writer task: sends messages to the WebSocket
    let write_task = tokio::spawn(async move {
        while let Some(text) = msg_rx.recv().await {
            if ws_sender.send(Message::Text(text)).await.is_err() {
                break;
            }
        }
    });

    // Subscription update channel
    let (sub_tx, mut sub_rx) = tokio::sync::mpsc::channel::<(bool, bool)>(16);

    // Broadcast forwarder task
    let msg_tx_clone = msg_tx.clone();
    let broadcast_task = tokio::spawn(async move {
        let mut sub_prices = false;
        let mut sub_intents = false;

        loop {
            tokio::select! {
                result = broadcast_rx.recv() => {
                    match result {
                        Ok(event) => {
                            let msg = match &event {
                                BroadcastEvent::Price(p) if sub_prices => {
                                    serde_json::to_string(p).ok()
                                }
                                BroadcastEvent::Intent(i) if sub_intents => {
                                    serde_json::to_string(i).ok()
                                }
                                _ => None,
                            };
                            if let Some(text) = msg {
                                if msg_tx_clone.send(text).await.is_err() {
                                    break;
                                }
                            }
                        }
                        Err(broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(_) => break,
                    }
                }
                Some((p, i)) = sub_rx.recv() => {
                    sub_prices = p;
                    sub_intents = i;
                }
                else => break,
            }
        }
    });

    // Main loop: read client messages
    while let Some(Ok(msg)) = ws_receiver.next().await {
        match msg {
            Message::Text(text) => {
                if let Ok(sub) = serde_json::from_str::<SubscribeMessage>(&text) {
                    match sub.subscribe.as_str() {
                        "prices" => {
                            subscribed_prices = true;
                            let _ = sub_tx.send((subscribed_prices, subscribed_intents)).await;
                            let _ = msg_tx
                                .send(r#"{"subscribed":"prices"}"#.to_string())
                                .await;
                        }
                        "intents" => {
                            subscribed_intents = true;
                            let _ = sub_tx.send((subscribed_prices, subscribed_intents)).await;
                            let _ = msg_tx
                                .send(r#"{"subscribed":"intents"}"#.to_string())
                                .await;
                        }
                        _ => {
                            let _ = msg_tx
                                .send(r#"{"error":"unknown channel"}"#.to_string())
                                .await;
                        }
                    }
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    // Clean up
    drop(msg_tx);
    drop(sub_tx);
    broadcast_task.abort();
    let _ = write_task.await;

    // Decrement connection counter.
    state.ws_connections.fetch_sub(1, Ordering::Relaxed);
}

/// Broadcast a new intent event to all WebSocket subscribers.
pub fn broadcast_intent(tx: &broadcast::Sender<BroadcastEvent>, intent: &crate::app::StoredIntent) {
    let _ = tx.send(BroadcastEvent::Intent(IntentUpdate {
        channel: "intents",
        intent_id: intent.intent_id.clone(),
        sender: intent.sender.clone(),
        sell_token: intent.sell_token.clone(),
        buy_token: intent.buy_token.clone(),
        sell_amount: intent.sell_amount.clone(),
        status: intent.status.clone(),
    }));
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/ws", get(ws_handler))
}

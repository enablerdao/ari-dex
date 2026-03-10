//! Core order book data structure.

use std::collections::BTreeMap;

use ari_core::{LimitOrder, OrderSide, TokenPair};

/// A price-time priority order book for a single token pair.
#[derive(Debug, Clone)]
pub struct OrderBook {
    /// The token pair this book covers.
    pub pair: TokenPair,
    /// Buy orders indexed by price (descending).
    bids: BTreeMap<u128, Vec<LimitOrder>>,
    /// Sell orders indexed by price (ascending).
    asks: BTreeMap<u128, Vec<LimitOrder>>,
    /// Next order ID.
    next_id: u64,
}

impl OrderBook {
    /// Creates a new empty order book for the given token pair.
    pub fn new(pair: TokenPair) -> Self {
        Self {
            pair,
            bids: BTreeMap::new(),
            asks: BTreeMap::new(),
            next_id: 1,
        }
    }

    /// Adds a limit order to the book.
    ///
    /// Returns the assigned order ID.
    pub fn add_order(&mut self, mut order: LimitOrder) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        order.id = id;

        match order.side {
            OrderSide::Buy => {
                self.bids.entry(order.price).or_default().push(order);
            }
            OrderSide::Sell => {
                self.asks.entry(order.price).or_default().push(order);
            }
        }

        id
    }

    /// Cancels an order by its ID.
    ///
    /// Returns the cancelled order if found.
    pub fn cancel_order(&mut self, order_id: u64) -> Option<LimitOrder> {
        // Search bids
        for orders in self.bids.values_mut() {
            if let Some(pos) = orders.iter().position(|o| o.id == order_id) {
                return Some(orders.remove(pos));
            }
        }
        // Search asks
        for orders in self.asks.values_mut() {
            if let Some(pos) = orders.iter().position(|o| o.id == order_id) {
                return Some(orders.remove(pos));
            }
        }
        None
    }

    /// Attempts to match crossing orders in the book.
    ///
    /// Returns a list of (buy_order_id, sell_order_id, matched_quantity) tuples.
    pub fn match_orders(&mut self) -> Vec<(u64, u64, [u8; 32])> {
        // TODO: Implement price-time priority matching
        Vec::new()
    }

    /// Returns the best bid price, if any.
    pub fn best_bid(&self) -> Option<u128> {
        self.bids.keys().next_back().copied()
    }

    /// Returns the best ask price, if any.
    pub fn best_ask(&self) -> Option<u128> {
        self.asks.keys().next().copied()
    }
}

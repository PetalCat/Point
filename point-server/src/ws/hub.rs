use std::sync::Arc;

use dashmap::DashMap;
use tokio::sync::mpsc;

/// Sender half used to push bytes into a WebSocket connection.
pub type WsSender = mpsc::UnboundedSender<Vec<u8>>;

/// A single connection tracked by (unique_id, sender).
type ConnEntry = (String, WsSender);

/// Central registry of all active WebSocket connections keyed by user_id.
#[derive(Clone)]
pub struct Hub {
    conns: Arc<DashMap<String, Vec<ConnEntry>>>,
}

impl Hub {
    pub fn new() -> Self {
        Self {
            conns: Arc::new(DashMap::new()),
        }
    }

    /// Register a new connection for a user. Returns the connection UUID for later removal.
    pub fn add_connection(&self, user_id: &str, tx: WsSender) -> String {
        let conn_id = uuid::Uuid::new_v4().to_string();
        self.conns
            .entry(user_id.to_string())
            .or_default()
            .push((conn_id.clone(), tx));
        conn_id
    }

    /// Remove a connection by its unique ID. If the user has no remaining connections the
    /// entry is removed entirely.
    pub fn remove_connection(&self, user_id: &str, conn_id: &str) {
        let mut remove_user = false;
        if let Some(mut entry) = self.conns.get_mut(user_id) {
            entry.retain(|(id, _)| id != conn_id);
            if entry.is_empty() {
                remove_user = true;
            }
        }
        if remove_user {
            self.conns.remove(user_id);
        }
    }

    /// Send bytes to every connection belonging to a user.
    pub fn send_to_user(&self, user_id: &str, data: &[u8]) {
        if let Some(entry) = self.conns.get(user_id) {
            for (_, tx) in entry.iter() {
                let _ = tx.send(data.to_vec());
            }
        }
    }

    /// Send bytes to multiple users.
    pub fn send_to_users(&self, user_ids: &[String], data: &[u8]) {
        for uid in user_ids {
            self.send_to_user(uid, data);
        }
    }

    /// Check whether a user has at least one active connection.
    pub fn is_online(&self, user_id: &str) -> bool {
        self.conns
            .get(user_id)
            .map(|e| !e.is_empty())
            .unwrap_or(false)
    }

    /// Return a list of all currently connected user IDs.
    pub fn online_users(&self) -> Vec<String> {
        self.conns.iter().map(|e| e.key().clone()).collect()
    }
}

//! Firebase Cloud Messaging — send push notifications via FCM v1 API.
//!
//! Uses the service account key at `firebase-admin.json` to authenticate.
//! Sends wake-up pushes with minimal data (no sensitive content hits Google).

use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::db;
use crate::db::DbPool;

#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
}

#[derive(Serialize)]
struct JwtClaims {
    iss: String,
    scope: String,
    aud: String,
    iat: i64,
    exp: i64,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
}

#[derive(Clone)]
pub struct FcmService {
    project_id: String,
    client_email: String,
    private_key: String,
    client: reqwest::Client,
    access_token: Arc<RwLock<Option<(String, i64)>>>, // (token, expires_at)
}

impl FcmService {
    /// Load from firebase-admin.json. Returns None if file doesn't exist.
    pub fn load(path: &str) -> Option<Self> {
        if !Path::new(path).exists() {
            tracing::warn!("Firebase admin key not found at {path}, FCM disabled");
            return None;
        }
        let data = std::fs::read_to_string(path).ok()?;
        let sa: ServiceAccount = serde_json::from_str(&data).ok()?;
        tracing::info!("FCM enabled for project {}", sa.project_id);
        Some(FcmService {
            project_id: sa.project_id,
            client_email: sa.client_email,
            private_key: sa.private_key,
            client: reqwest::Client::new(),
            access_token: Arc::new(RwLock::new(None)),
        })
    }

    /// Get a valid OAuth2 access token, refreshing if needed.
    async fn get_access_token(&self) -> Result<String, String> {
        // Check cached token
        {
            let cached = self.access_token.read().await;
            if let Some((token, expires_at)) = cached.as_ref() {
                if chrono::Utc::now().timestamp() < *expires_at - 60 {
                    return Ok(token.clone());
                }
            }
        }

        // Generate JWT
        let now = chrono::Utc::now().timestamp();
        let claims = JwtClaims {
            iss: self.client_email.clone(),
            scope: "https://www.googleapis.com/auth/firebase.messaging".to_string(),
            aud: "https://oauth2.googleapis.com/token".to_string(),
            iat: now,
            exp: now + 3600,
        };

        // Sign with RS256
        let key = jsonwebtoken::EncodingKey::from_rsa_pem(self.private_key.as_bytes())
            .map_err(|e| format!("Invalid private key: {e}"))?;
        let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
        let jwt = jsonwebtoken::encode(&header, &claims, &key)
            .map_err(|e| format!("JWT encode error: {e}"))?;

        // Exchange for access token
        let resp = self.client
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &jwt),
            ])
            .send()
            .await
            .map_err(|e| format!("Token request failed: {e}"))?;

        if !resp.status().is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("Token exchange failed: {body}"));
        }

        let token_resp: TokenResponse = resp.json().await
            .map_err(|e| format!("Token parse error: {e}"))?;

        // Cache it
        let mut cached = self.access_token.write().await;
        *cached = Some((token_resp.access_token.clone(), now + 3500));

        Ok(token_resp.access_token)
    }

    /// Send a wake-up push to a user. Contains NO sensitive data.
    pub async fn send_wake_push(&self, pool: &DbPool, user_id: &str, event_type: &str) {
        let tokens = match db::users::get_fcm_tokens(pool, user_id).await {
            Ok(t) => t,
            Err(e) => {
                tracing::error!(error = %e, "Failed to get FCM tokens");
                return;
            }
        };

        if tokens.is_empty() {
            return;
        }

        let access_token = match self.get_access_token().await {
            Ok(t) => t,
            Err(e) => {
                tracing::error!(error = %e, "Failed to get FCM access token");
                return;
            }
        };

        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );

        for fcm_token in tokens {
            let body = serde_json::json!({
                "message": {
                    "token": fcm_token,
                    "data": {
                        "type": event_type,
                        "t": chrono::Utc::now().timestamp().to_string(),
                    },
                    "android": {
                        "priority": "high",
                    },
                }
            });

            match self.client
                .post(&url)
                .bearer_auth(&access_token)
                .json(&body)
                .send()
                .await
            {
                Ok(resp) => {
                    if !resp.status().is_success() {
                        let status = resp.status();
                        let body = resp.text().await.unwrap_or_default();
                        tracing::warn!(status = %status, body = %body, "FCM send failed");
                    }
                }
                Err(e) => {
                    tracing::error!(error = %e, "FCM request failed");
                }
            }
        }
    }
}

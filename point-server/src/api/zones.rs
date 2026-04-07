use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct RequestConsentBody {
    pub user_id: String,
}

#[derive(Debug, Serialize)]
pub struct ZoneConsentResponse {
    pub zone_owner_id: String,
    pub consenter_id: String,
    pub status: String,
    pub created_at: String,
}

/// POST /api/zones/consent/request — Request consent from someone to evaluate
/// their location against your personal zones.
pub async fn request_consent(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<RequestConsentBody>,
) -> Result<Json<ZoneConsentResponse>, AppError> {
    if body.user_id == user.user_id {
        return Err(AppError::BadRequest("cannot request zone consent from yourself".into()));
    }

    // Verify target user exists
    let target = db::users::get_user_by_id(&state.pool, &body.user_id).await?;
    if target.is_none() {
        return Err(AppError::NotFound("user not found".into()));
    }

    let consent = db::zone_consents::request_consent(&state.pool, &user.user_id, &body.user_id)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(ref db_err) = e {
                if db_err.message().contains("UNIQUE") {
                    return AppError::Conflict("zone consent request already exists".into());
                }
            }
            AppError::Internal(e.to_string())
        })?;

    // Push WS notification to the target user
    let notify = serde_json::json!({
        "type": "zone.consent_request",
        "from_user_id": user.user_id,
    });
    state.hub.send_to_user(
        &body.user_id,
        serde_json::to_vec(&notify).unwrap_or_default().as_slice(),
    );

    // FCM wake-up push if offline
    if let Some(ref fcm) = state.fcm {
        let pool = state.pool.clone();
        let to = body.user_id.clone();
        let fcm = fcm.clone();
        tokio::spawn(async move {
            fcm.send_wake_push(&pool, &to, "zone.consent_request").await;
        });
    }

    Ok(Json(ZoneConsentResponse {
        zone_owner_id: consent.zone_owner_id,
        consenter_id: consent.consenter_id,
        status: consent.status,
        created_at: consent.created_at,
    }))
}

/// GET /api/zones/consent/incoming — List incoming consent requests (people who
/// want to track you with their zones).
pub async fn list_incoming(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<ZoneConsentResponse>>, AppError> {
    let consents =
        db::zone_consents::get_consent_requests_for_user(&state.pool, &user.user_id).await?;

    Ok(Json(
        consents
            .into_iter()
            .map(|c| ZoneConsentResponse {
                zone_owner_id: c.zone_owner_id,
                consenter_id: c.consenter_id,
                status: c.status,
                created_at: c.created_at,
            })
            .collect(),
    ))
}

/// GET /api/zones/consent/granted — List who you've granted consent to (accepted).
pub async fn list_granted(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<ZoneConsentResponse>>, AppError> {
    // The user is the consenter; find all accepted consents where they are consenter
    let rows = sqlx::query(
        "SELECT zone_owner_id, consenter_id, status, created_at \
         FROM zone_consents WHERE consenter_id = ? AND status = 'accepted' \
         ORDER BY created_at DESC",
    )
    .bind(&user.user_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(
        rows.iter()
            .map(|r| ZoneConsentResponse {
                zone_owner_id: r.get("zone_owner_id"),
                consenter_id: r.get("consenter_id"),
                status: r.get("status"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

/// POST /api/zones/consent/{owner_id}/accept — Accept a consent request.
pub async fn accept_consent(
    State(state): State<AppState>,
    user: AuthUser,
    Path(owner_id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::zone_consents::accept_consent(&state.pool, &owner_id, &user.user_id)
        .await
        .map_err(|e| match e {
            sqlx::Error::RowNotFound => {
                AppError::NotFound("consent request not found or not addressed to you".into())
            }
            other => AppError::Internal(other.to_string()),
        })?;

    // Notify the zone owner
    let notify = serde_json::json!({
        "type": "zone.consent_accepted",
        "by_user_id": user.user_id,
    });
    state.hub.send_to_user(
        &owner_id,
        serde_json::to_vec(&notify).unwrap_or_default().as_slice(),
    );

    if let Some(ref fcm) = state.fcm {
        let pool = state.pool.clone();
        let to = owner_id.clone();
        let fcm = fcm.clone();
        tokio::spawn(async move {
            fcm.send_wake_push(&pool, &to, "zone.consent_accepted").await;
        });
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// POST /api/zones/consent/{owner_id}/reject — Reject a consent request.
pub async fn reject_consent(
    State(state): State<AppState>,
    user: AuthUser,
    Path(owner_id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::zone_consents::reject_consent(&state.pool, &owner_id, &user.user_id)
        .await
        .map_err(|e| match e {
            sqlx::Error::RowNotFound => {
                AppError::NotFound("consent request not found or not addressed to you".into())
            }
            other => AppError::Internal(other.to_string()),
        })?;

    // Notify the zone owner
    let notify = serde_json::json!({
        "type": "zone.consent_rejected",
        "by_user_id": user.user_id,
    });
    state.hub.send_to_user(
        &owner_id,
        serde_json::to_vec(&notify).unwrap_or_default().as_slice(),
    );

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// DELETE /api/zones/consent/{owner_id} — Revoke previously granted consent.
pub async fn revoke_consent(
    State(state): State<AppState>,
    user: AuthUser,
    Path(owner_id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::zone_consents::revoke_consent(&state.pool, &owner_id, &user.user_id)
        .await
        .map_err(|e| match e {
            sqlx::Error::RowNotFound => AppError::NotFound("consent not found".into()),
            other => AppError::Internal(other.to_string()),
        })?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

//! Integration tests for the location authorization boundary (P0-04, P0-05).
//!
//! These lock in the invariant that the server only authorizes location
//! delivery when a real relationship exists: permanent share, active temp
//! share, or sharing-enabled group membership. Regression here would silently
//! re-open the privacy holes the 2026-06-02 audit found.

use point_server::db;
use sqlx::sqlite::SqlitePoolOptions;

/// Spin up an in-memory SQLite DB with all migrations applied.
async fn test_pool() -> db::DbPool {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("connect in-memory sqlite");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations");
    pool
}

async fn mk_user(pool: &db::DbPool, id: &str) {
    db::users::create_user(pool, id, id, "hash", false)
        .await
        .expect("create user");
}

/// Accept a share by creating a request then accepting it (mirrors the API path).
async fn make_permanent_share(pool: &db::DbPool, a: &str, b: &str) {
    let req_id = format!("req-{a}-{b}");
    db::shares::create_request(pool, &req_id, a, b)
        .await
        .expect("create request");
    db::shares::accept_request(pool, &req_id, b)
        .await
        .expect("accept request");
}

#[tokio::test]
async fn no_relationship_cannot_send() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;

    // No share of any kind between alice and bob.
    let allowed = db::shares::can_send_to_user(&pool, "alice", "bob")
        .await
        .unwrap();
    assert!(!allowed, "strangers must not be able to send location");
}

#[tokio::test]
async fn permanent_share_allows_both_directions() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;
    make_permanent_share(&pool, "alice", "bob").await;

    assert!(db::shares::can_send_to_user(&pool, "alice", "bob").await.unwrap());
    assert!(db::shares::can_send_to_user(&pool, "bob", "alice").await.unwrap());
}

#[tokio::test]
async fn active_temp_share_allows_only_sender_to_recipient() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;

    // Alice shares temporarily TO bob, expiring far in the future.
    db::shares::create_temp_share(
        &pool,
        "temp-1",
        "alice",
        Some("bob"),
        None,
        "exact",
        "2999-01-01 00:00:00",
    )
    .await
    .unwrap();

    // Directional: alice -> bob allowed.
    assert!(db::shares::can_send_to_user(&pool, "alice", "bob").await.unwrap());
    // bob -> alice NOT allowed (bob never shared with alice).
    assert!(!db::shares::can_send_to_user(&pool, "bob", "alice").await.unwrap());
}

#[tokio::test]
async fn expired_temp_share_does_not_authorize() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;

    db::shares::create_temp_share(
        &pool,
        "temp-expired",
        "alice",
        Some("bob"),
        None,
        "exact",
        "2000-01-01 00:00:00", // already expired
    )
    .await
    .unwrap();

    assert!(
        !db::shares::can_send_to_user(&pool, "alice", "bob").await.unwrap(),
        "expired temp share must not authorize delivery"
    );
}

#[tokio::test]
async fn group_membership_requires_sharing_enabled() {
    let pool = test_pool().await;
    mk_user(&pool, "owner").await;
    mk_user(&pool, "member").await;
    mk_user(&pool, "stranger").await;

    db::groups::create_group(&pool, "grp-1", "Family", "owner")
        .await
        .unwrap();
    db::groups::add_member(&pool, "grp-1", "member", "member", "exact")
        .await
        .unwrap();

    // Owner and member are sharing members.
    assert!(db::groups::is_sharing_member(&pool, "grp-1", "owner").await.unwrap());
    assert!(db::groups::is_sharing_member(&pool, "grp-1", "member").await.unwrap());
    // Stranger is not a member at all.
    assert!(!db::groups::is_sharing_member(&pool, "grp-1", "stranger").await.unwrap());

    // Member turns sharing OFF — must no longer be a sharing member.
    db::groups::update_my_settings(&pool, "grp-1", "member", None, Some(false), None)
        .await
        .unwrap();
    assert!(
        !db::groups::is_sharing_member(&pool, "grp-1", "member").await.unwrap(),
        "member with sharing=false must not authorize group delivery"
    );
}

#[tokio::test]
async fn removed_share_revokes_authorization() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;
    make_permanent_share(&pool, "alice", "bob").await;
    assert!(db::shares::can_send_to_user(&pool, "alice", "bob").await.unwrap());

    db::shares::remove_share(&pool, "alice", "bob").await.unwrap();
    assert!(
        !db::shares::can_send_to_user(&pool, "alice", "bob").await.unwrap(),
        "removed share must revoke authorization"
    );
}

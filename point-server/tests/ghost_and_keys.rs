//! Tests for ghost-flag persistence (P1-09) and MLS key-package consumption
//! (P0-03.5). Key packages are single-use in MLS; the server must not hand the
//! same package out twice (would break forward secrecy / cause join failures).

use point_server::db;
use sqlx::sqlite::SqlitePoolOptions;

async fn test_pool() -> db::DbPool {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .unwrap();
    sqlx::migrate!("./migrations").run(&pool).await.unwrap();
    pool
}

async fn mk_user(pool: &db::DbPool, id: &str) {
    db::users::create_user(pool, id, id, "hash", false).await.unwrap();
}

#[tokio::test]
async fn ghost_flag_round_trips() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;

    // Default is not ghosted.
    assert!(!db::users::is_ghost_active(&pool, "alice").await.unwrap());

    db::users::set_ghost_flag(&pool, "alice", true).await.unwrap();
    assert!(db::users::is_ghost_active(&pool, "alice").await.unwrap());

    db::users::set_ghost_flag(&pool, "alice", false).await.unwrap();
    assert!(!db::users::is_ghost_active(&pool, "alice").await.unwrap());
}

#[tokio::test]
async fn ghost_flag_unknown_user_defaults_false() {
    let pool = test_pool().await;
    // No user created — is_ghost_active should return Ok(false), not error,
    // so the caller's fail-closed logic is driven by real DB errors only.
    assert!(!db::users::is_ghost_active(&pool, "nobody").await.unwrap());
}

#[tokio::test]
async fn key_package_can_be_deleted_after_use() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;

    db::mls::store_key_package(&pool, "kp-1", "alice", b"package-one").await.unwrap();
    db::mls::store_key_package(&pool, "kp-2", "alice", b"package-two").await.unwrap();

    let pkgs = db::mls::get_key_packages(&pool, "alice").await.unwrap();
    assert_eq!(pkgs.len(), 2);

    // Consume one (mirrors get_keys handler behavior).
    db::mls::delete_key_package(&pool, &pkgs[0].id).await.unwrap();

    let remaining = db::mls::get_key_packages(&pool, "alice").await.unwrap();
    assert_eq!(remaining.len(), 1, "consumed key package must be gone");
    assert_ne!(remaining[0].id, pkgs[0].id);
}

//! Tests for visibility modes (saved audiences) — backend for the redesign's
//! Focus-style mode picker.

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
async fn mode_crud_roundtrip() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;

    let m = db::visibility::create_mode(
        &pool, "m1", "alice", "Work", "briefcase",
        &["g-eng".to_string()], &["bob".to_string()],
    ).await.unwrap();
    assert_eq!(m.name, "Work");
    assert_eq!(m.group_ids, vec!["g-eng"]);
    assert_eq!(m.user_ids, vec!["bob"]);

    // List returns it.
    let modes = db::visibility::list_modes(&pool, "alice").await.unwrap();
    assert_eq!(modes.len(), 1);

    // Update changes membership.
    db::visibility::update_mode(
        &pool, "m1", "alice", "Work", "briefcase",
        &["g-eng".to_string(), "g-design".to_string()], &[],
    ).await.unwrap();
    let updated = db::visibility::get_mode(&pool, "m1").await.unwrap().unwrap();
    assert_eq!(updated.group_ids.len(), 2);
    assert!(updated.user_ids.is_empty());

    // Delete removes it.
    db::visibility::delete_mode(&pool, "m1", "alice").await.unwrap();
    assert!(db::visibility::list_modes(&pool, "alice").await.unwrap().is_empty());
}

#[tokio::test]
async fn active_mode_pointer() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    db::visibility::create_mode(&pool, "m1", "alice", "Family", "home", &[], &[])
        .await.unwrap();

    // Default is none (Custom).
    assert_eq!(db::visibility::get_active_mode(&pool, "alice").await.unwrap(), None);

    db::visibility::set_active_mode(&pool, "alice", Some("m1")).await.unwrap();
    assert_eq!(
        db::visibility::get_active_mode(&pool, "alice").await.unwrap(),
        Some("m1".to_string())
    );

    // Back to custom.
    db::visibility::set_active_mode(&pool, "alice", None).await.unwrap();
    assert_eq!(db::visibility::get_active_mode(&pool, "alice").await.unwrap(), None);
}

#[tokio::test]
async fn modes_are_per_user() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;
    db::visibility::create_mode(&pool, "m1", "alice", "A", "users", &[], &[]).await.unwrap();
    db::visibility::create_mode(&pool, "m2", "bob", "B", "users", &[], &[]).await.unwrap();

    assert_eq!(db::visibility::list_modes(&pool, "alice").await.unwrap().len(), 1);
    assert_eq!(db::visibility::list_modes(&pool, "bob").await.unwrap().len(), 1);
}

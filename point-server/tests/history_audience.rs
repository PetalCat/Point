//! Tests for audience-bound location history (P1-10): a recipient must only
//! be able to fetch history rows addressed to an audience they belong to.

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
async fn audience_filter_excludes_other_audiences() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;
    mk_user(&pool, "carol").await;

    // Alice's history: one point sent to bob (user), one sent to group "fam".
    db::history::store_history_point(&pool, "h1", "alice", b"blob-bob", "gps", 100, "user", "bob")
        .await.unwrap();
    db::history::store_history_point(&pool, "h2", "alice", b"blob-fam", "gps", 200, "group", "fam")
        .await.unwrap();
    // One point sent to a group carol is NOT in.
    db::history::store_history_point(&pool, "h3", "alice", b"blob-work", "gps", 300, "group", "work")
        .await.unwrap();

    // Bob (direct recipient, no groups) sees only the point addressed to him.
    let bob_view = db::history::get_history_for_audience(&pool, "alice", "bob", &[], 0, 100)
        .await.unwrap();
    assert_eq!(bob_view.len(), 1);
    assert_eq!(bob_view[0].id, "h1");

    // Carol, a member of "fam" only, sees just the fam point — not work, not the
    // direct-to-bob point.
    let carol_view = db::history::get_history_for_audience(
        &pool, "alice", "carol", &["fam".to_string()], 0, 100,
    ).await.unwrap();
    assert_eq!(carol_view.len(), 1);
    assert_eq!(carol_view[0].id, "h2");
}

#[tokio::test]
async fn owner_sees_all_audiences() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;

    db::history::store_history_point(&pool, "h1", "alice", b"a", "gps", 100, "user", "bob")
        .await.unwrap();
    db::history::store_history_point(&pool, "h2", "alice", b"b", "gps", 200, "group", "fam")
        .await.unwrap();

    let own = db::history::get_own_history(&pool, "alice", 0, 100).await.unwrap();
    assert_eq!(own.len(), 2, "owner sees their full history across audiences");
}

#[tokio::test]
async fn legacy_null_audience_hidden_from_others() {
    let pool = test_pool().await;
    mk_user(&pool, "alice").await;
    mk_user(&pool, "bob").await;

    // Simulate a legacy row with NULL audience (pre-migration).
    sqlx::query(
        "INSERT INTO location_history (id, user_id, encrypted_blob, source_type, timestamp) \
         VALUES ('legacy', 'alice', X'00', 'gps', 50)",
    )
    .execute(&pool)
    .await
    .unwrap();

    // Bob (would-be recipient) must NOT see the legacy unaudienced row.
    let bob_view = db::history::get_history_for_audience(&pool, "alice", "bob", &[], 0, 100)
        .await.unwrap();
    assert!(bob_view.is_empty(), "legacy NULL-audience rows are owner-only");

    // But the owner still sees it.
    let own = db::history::get_own_history(&pool, "alice", 0, 100).await.unwrap();
    assert_eq!(own.len(), 1);
}

CREATE TABLE IF NOT EXISTS location_history (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_blob BLOB NOT NULL,
    source_type TEXT NOT NULL DEFAULT 'native',
    timestamp INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_location_history_user ON location_history(user_id, timestamp);

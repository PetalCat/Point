CREATE TABLE IF NOT EXISTS key_packages (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_package BLOB NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS mls_messages (
    id TEXT PRIMARY KEY,
    recipient_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL,  -- 'welcome' or 'commit'
    group_id TEXT NOT NULL,
    sender_id TEXT NOT NULL,
    payload BLOB NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_mls_messages_recipient ON mls_messages(recipient_id, processed);

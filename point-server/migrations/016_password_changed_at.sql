-- Track when password was last changed for token revocation
ALTER TABLE users ADD COLUMN password_changed_at TEXT NOT NULL DEFAULT (datetime('now'));

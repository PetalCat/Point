-- Track when password was last changed for token revocation
-- SQLite ALTER TABLE requires constant defaults, so use a fixed epoch
ALTER TABLE users ADD COLUMN password_changed_at TEXT NOT NULL DEFAULT '2000-01-01 00:00:00';

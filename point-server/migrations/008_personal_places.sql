-- Personal places: owned by a user, not tied to any group
ALTER TABLE places ADD COLUMN user_id TEXT;
ALTER TABLE places ADD COLUMN is_personal BOOLEAN NOT NULL DEFAULT FALSE;

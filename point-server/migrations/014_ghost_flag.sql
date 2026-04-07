-- Ghost mode server-side safety net
-- Coarse flag: when true, server drops ALL location broadcasts from this user
ALTER TABLE users ADD COLUMN ghost_active BOOLEAN NOT NULL DEFAULT FALSE;

-- P1-10: bind location history to the audience it was sent to, so a recipient
-- can only fetch history for periods/audiences they were actually part of.
-- Legacy rows have NULL audience and are only visible to the owner.
ALTER TABLE location_history ADD COLUMN recipient_type TEXT;
ALTER TABLE location_history ADD COLUMN recipient_id TEXT;
CREATE INDEX IF NOT EXISTS idx_history_audience
  ON location_history (recipient_type, recipient_id);

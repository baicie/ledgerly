CREATE UNIQUE INDEX IF NOT EXISTS idx_device_sessions_refresh_token_hash
ON device_sessions (refresh_token_hash);

CREATE INDEX IF NOT EXISTS idx_device_sessions_active_created_at
ON device_sessions (created_at)
WHERE revoked_at IS NULL;

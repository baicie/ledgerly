CREATE TABLE IF NOT EXISTS audit_events (
    id TEXT PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_type TEXT NOT NULL,
    actor_id TEXT,
    action TEXT NOT NULL,
    outcome TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    request_id TEXT,
    metadata JSONB NOT NULL DEFAULT '{}',
    CONSTRAINT audit_actor_type_check CHECK (actor_type IN ('user', 'system')),
    CONSTRAINT audit_outcome_check CHECK (outcome IN ('success', 'failure', 'denied')),
    CONSTRAINT audit_metadata_size_check CHECK (octet_length(metadata::text) <= 4096)
);

CREATE INDEX IF NOT EXISTS idx_audit_events_actor
ON audit_events (actor_id, id DESC)
WHERE actor_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_audit_events_action_outcome
ON audit_events (action, outcome, id DESC);

CREATE INDEX IF NOT EXISTS idx_audit_events_occurred_at
ON audit_events (occurred_at DESC);

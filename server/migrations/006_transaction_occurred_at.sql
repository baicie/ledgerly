-- Business timestamp for transaction ordering, reporting, and synchronization.
ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ;

UPDATE transactions
SET occurred_at = created_at
WHERE occurred_at IS NULL;

UPDATE sync_changes AS sc
SET payload = jsonb_set(
    sc.payload,
    '{occurredAt}',
    to_jsonb(to_char(
        t.occurred_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )),
    true
)
FROM transactions AS t
WHERE sc.entity_type = 'transaction'
  AND sc.operation = 'upsert'
  AND sc.entity_id = t.id
  AND sc.book_id = t.book_id
  AND jsonb_typeof(sc.payload) = 'object'
  AND NOT sc.payload ? 'occurredAt';

ALTER TABLE transactions
ALTER COLUMN occurred_at SET DEFAULT now();

ALTER TABLE transactions
ALTER COLUMN occurred_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_book_occurred_at
ON transactions (book_id, occurred_at)
WHERE deleted_at IS NULL;

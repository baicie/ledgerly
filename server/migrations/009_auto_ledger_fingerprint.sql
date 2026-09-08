-- Cross-device idempotency for auto-ledger transactions.
--
-- A `source_event_fingerprint` is a SHA-256 hash of the business fields that
-- uniquely identify one payment event (direction + amount + occurred_at +
-- merchant + book_id).  Two devices that independently capture the same
-- WeChat/Alipay notification will derive the same fingerprint, and the
-- partial unique index below prevents them from both creating a transaction
-- row.
--
-- The index is a partial unique index so it does not affect manual
-- transactions that have NULL fingerprint.
ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS source_event_fingerprint TEXT;

-- One auto_ledger transaction per (book_id, fingerprint) pair.
CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_auto_event
    ON transactions (book_id, source_event_fingerprint)
    WHERE source = 'auto_ledger'
      AND deleted_at IS NULL
      AND source_event_fingerprint IS NOT NULL;

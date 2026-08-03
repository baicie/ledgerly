-- Phase 5+ / BE-6 tables
ALTER TABLE books ADD COLUMN IF NOT EXISTS base_currency TEXT NOT NULL DEFAULT 'CNY';

CREATE TABLE IF NOT EXISTS fx_rates (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    base_currency TEXT NOT NULL,
    quote_currency TEXT NOT NULL,
    rate NUMERIC NOT NULL,
    as_of TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (book_id, base_currency, quote_currency)
);

CREATE TABLE IF NOT EXISTS transaction_revisions (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    transaction_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    operation TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tx_revisions_tx
ON transaction_revisions (book_id, transaction_id, version);

CREATE TABLE IF NOT EXISTS subscriptions (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    plan TEXT NOT NULL DEFAULT 'free',
    status TEXT NOT NULL DEFAULT 'active',
    expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

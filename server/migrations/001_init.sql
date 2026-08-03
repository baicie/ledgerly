-- BE-0/1/2 core schema
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS device_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    device_id TEXT NOT NULL,
    refresh_token_hash TEXT NOT NULL,
    device_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS books (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS book_members (
    book_id UUID NOT NULL REFERENCES books(id),
    user_id UUID NOT NULL REFERENCES users(id),
    role TEXT NOT NULL,
    PRIMARY KEY (book_id, user_id)
);

CREATE TABLE IF NOT EXISTS accounts (
    id UUID PRIMARY KEY,
    book_id UUID NOT NULL REFERENCES books(id),
    name TEXT NOT NULL,
    account_type TEXT NOT NULL,
    currency_code TEXT NOT NULL,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY,
    book_id UUID NOT NULL REFERENCES books(id),
    description TEXT,
    version BIGINT NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transaction_entries (
    id UUID PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES transactions(id),
    account_id UUID NOT NULL REFERENCES accounts(id),
    amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0),
    currency_code TEXT NOT NULL,
    entry_index INT NOT NULL,
    UNIQUE (transaction_id, entry_index)
);

CREATE TABLE IF NOT EXISTS sync_mutations (
    book_id UUID NOT NULL,
    device_id TEXT NOT NULL,
    mutation_id TEXT NOT NULL,
    status TEXT NOT NULL,
    result_code TEXT NOT NULL,
    entity_version BIGINT,
    response_payload JSONB,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (book_id, device_id, mutation_id)
);

CREATE TABLE IF NOT EXISTS sync_changes (
    sequence BIGSERIAL PRIMARY KEY,
    book_id UUID NOT NULL,
    commit_id UUID NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    entity_version BIGINT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sync_changes_book_sequence
ON sync_changes (book_id, sequence);

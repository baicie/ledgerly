ALTER TABLE attachments
    ADD COLUMN IF NOT EXISTS file_name TEXT;

CREATE INDEX IF NOT EXISTS idx_attachments_book_created
    ON attachments (book_id, created_at DESC);

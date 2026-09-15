ALTER TABLE attachments
    ADD COLUMN IF NOT EXISTS upload_mode TEXT NOT NULL DEFAULT 'single';

ALTER TABLE attachments
    ADD COLUMN IF NOT EXISTS multipart_upload_id TEXT;

ALTER TABLE attachments
    ADD COLUMN IF NOT EXISTS multipart_parts JSONB NOT NULL DEFAULT '[]'::jsonb;

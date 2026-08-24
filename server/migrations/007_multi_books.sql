-- Multi-book management is additive. Existing book ids and all ledger rows remain unchanged.
CREATE INDEX IF NOT EXISTS idx_books_owner_created_at
ON books (owner_id, created_at);

CREATE INDEX IF NOT EXISTS idx_book_members_user_book
ON book_members (user_id, book_id);

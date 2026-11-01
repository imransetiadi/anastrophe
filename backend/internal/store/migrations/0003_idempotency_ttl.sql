-- Pembersihan berkala baris idempotency (temuan review backend minor 9).
CREATE INDEX idempotency_keys_created_at_idx ON idempotency_keys (created_at);

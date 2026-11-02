-- Rahasia enrolment (ADR-0040): SHA-256 rahasia yang dibuat app saat enrolment. Hanya kredensial pertama
-- yang memakainya, dan nilainya dihapus setelah kredensial itu tersimpan.
ALTER TABLE card_instances ADD COLUMN provisioning_key_hash bytea CHECK (provisioning_key_hash IS NULL OR length(provisioning_key_hash) = 32);

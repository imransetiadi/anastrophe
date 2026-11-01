-- Nonce perpanjangan sertifikat (FR-45, ADR-0023): 32 B acak, sekali pakai, terikat ke satu
-- kredensial, berlaku singkat. Baris kedaluwarsa dibersihkan berkala.
CREATE TABLE renewal_challenges (
    nonce bytea PRIMARY KEY CHECK (length(nonce) = 32),
    credential_id uuid NOT NULL REFERENCES credentials(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    used_at timestamptz
);

CREATE INDEX renewal_challenges_expires_at_idx ON renewal_challenges (expires_at);

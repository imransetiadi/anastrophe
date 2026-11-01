-- Siklus hidup kartu oleh operator (FR-51, ADR-0036) dan token baca status (ADR-0037).
-- Hanya SHA-256 token yang disimpan; token mentah tidak pernah sampai ke database.
ALTER TABLE card_instances ADD COLUMN status_token_hash bytea CHECK (status_token_hash IS NULL OR length(status_token_hash) = 32);

-- Kredensial yang dicabut, untuk sinkron reader (SDD §8.4.3). expires_at = not_after sertifikat,
-- sehingga baris boleh dibuang setelah sertifikatnya kedaluwarsa.
CREATE TABLE denylist_entries (
    site_id uuid NOT NULL REFERENCES sites(id),
    cred_id bytea NOT NULL,
    revoked_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (site_id, cred_id)
);

-- Registri kartu fisik (FR-11, FR-52; ADR-0031). Hanya HMAC per gedung, tidak pernah identitas
-- kartu atau kontak mentah (CLAUDE.md aturan 6).
CREATE TABLE physical_cards (
    id uuid PRIMARY KEY,
    site_id uuid NOT NULL REFERENCES sites(id),
    card_id_hmac bytea NOT NULL CHECK (length(card_id_hmac) = 32),
    holder_contact_hmac bytea CHECK (holder_contact_hmac IS NULL OR length(holder_contact_hmac) = 32),
    zones_bitmap bigint NOT NULL DEFAULT 0, -- pola 64 bit (uint64 disimpan sebagai int64)
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REMOVED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, card_id_hmac)
);

-- Card instance tertaut ke kartu terdaftar (null untuk data tracer lama). ADR-0032: perangkat
-- tambahan bisa ditolak operator, jadi status bertambah REJECTED.
ALTER TABLE card_instances ADD COLUMN physical_card_id uuid REFERENCES physical_cards(id);
CREATE INDEX card_instances_physical_card_idx ON card_instances (physical_card_id) WHERE physical_card_id IS NOT NULL;
ALTER TABLE card_instances DROP CONSTRAINT card_instances_status_check;
ALTER TABLE card_instances ADD CONSTRAINT card_instances_status_check
    CHECK (status IN ('PENDING_APPROVAL', 'PROVISIONING', 'ACTIVE', 'SUSPENDED', 'REVOKED', 'DELETED', 'REJECTED'));

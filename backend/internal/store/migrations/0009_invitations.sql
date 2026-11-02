-- Undangan enrolment sekali pakai (FR-12, FR-53; ADR-0033). Hanya hash token yang disimpan; undangan
-- dianggap terpakai selama punya card instance yang tidak ABANDONED (ADR-0034).
CREATE TABLE invitations (
    id uuid PRIMARY KEY,
    site_id uuid NOT NULL REFERENCES sites(id),
    physical_card_id uuid REFERENCES physical_cards(id),
    contact_hmac bytea CHECK (contact_hmac IS NULL OR length(contact_hmac) = 32),
    token_hash bytea NOT NULL UNIQUE CHECK (length(token_hash) = 32),
    zones_bitmap bigint NOT NULL DEFAULT 0, -- pola 64 bit (uint64 disimpan sebagai int64)
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL
);

ALTER TABLE card_instances ADD COLUMN invitation_id uuid REFERENCES invitations(id);
CREATE INDEX card_instances_invitation_idx ON card_instances (invitation_id) WHERE invitation_id IS NOT NULL;

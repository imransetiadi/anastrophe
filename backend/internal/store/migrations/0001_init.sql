-- Subset skema SDD §8.1 untuk backend R1 tracer bullet.
-- card_instances disederhanakan (device + site) sampai rencana enrolment/keanggotaan.

CREATE TABLE organizations (
    id uuid PRIMARY KEY,
    name text NOT NULL,
    region text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sites (
    id uuid PRIMARY KEY,
    org_id uuid NOT NULL REFERENCES organizations(id),
    name text NOT NULL,
    country text NOT NULL,
    timezone text NOT NULL,
    site_code bytea NOT NULL UNIQUE CHECK (length(site_code) = 8), -- site_id 8 B di CredentialCert
    policy jsonb NOT NULL DEFAULT '{}',
    site_ca_key_ref text NOT NULL DEFAULT ''                        -- referensi KMS/HSM, bukan kunci
);

CREATE TABLE reader_groups (
    id bytea PRIMARY KEY CHECK (length(id) = 8),
    site_id uuid NOT NULL REFERENCES sites(id),
    pubkey bytea NOT NULL CHECK (length(pubkey) = 65),
    next_pubkey bytea CHECK (next_pubkey IS NULL OR length(next_pubkey) = 65),
    rotated_at timestamptz
);

CREATE TABLE devices (
    id uuid PRIMARY KEY,
    status text NOT NULL DEFAULT 'ACTIVE',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE card_instances (
    id uuid PRIMARY KEY,
    device_id uuid NOT NULL REFERENCES devices(id),
    site_id uuid NOT NULL REFERENCES sites(id),
    status text NOT NULL CHECK (status IN ('PENDING_APPROVAL', 'PROVISIONING', 'ACTIVE', 'SUSPENDED', 'REVOKED', 'DELETED')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX card_instances_device_idx ON card_instances (device_id);

CREATE TABLE credentials (
    id uuid PRIMARY KEY,
    card_instance_id uuid NOT NULL REFERENCES card_instances(id),
    channel text NOT NULL CHECK (channel IN ('nfcHCE', 'ble', 'nfcSE')),
    cred_id bytea NOT NULL UNIQUE CHECK (length(cred_id) = 16),
    pubkey bytea NOT NULL CHECK (length(pubkey) = 65),
    cert bytea NOT NULL,
    not_after timestamptz NOT NULL,
    last_counter bigint NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'ACTIVE',
    revoked_at timestamptz,
    revoke_reason text
);

CREATE TABLE idempotency_keys (
    key text PRIMARY KEY,
    request_hash bytea NOT NULL,
    status integer NOT NULL,
    body bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

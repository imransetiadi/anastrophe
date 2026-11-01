-- Log audit append-only berantai hash per gedung (FR-54, ADR-0024). Rantai "platform" untuk
-- event tanpa gedung. Trigger menolak UPDATE/DELETE/TRUNCATE lewat jalur aplikasi.
CREATE TABLE audit_events (
    id bigserial PRIMARY KEY,
    chain text NOT NULL,
    site_id uuid REFERENCES sites(id),
    seq bigint NOT NULL CHECK (seq >= 1),
    at timestamptz NOT NULL,
    actor text NOT NULL,
    action text NOT NULL,
    subject text NOT NULL,
    data jsonb NOT NULL DEFAULT '{}',
    prev_hash bytea NOT NULL CHECK (length(prev_hash) = 32),
    hash bytea NOT NULL CHECK (length(hash) = 32),
    UNIQUE (chain, seq)
);

CREATE FUNCTION audit_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_events append-only';
END
$$;

CREATE TRIGGER audit_events_append_only BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION audit_events_append_only();

CREATE TRIGGER audit_events_no_truncate BEFORE TRUNCATE ON audit_events
    FOR EACH STATEMENT EXECUTE FUNCTION audit_events_append_only();

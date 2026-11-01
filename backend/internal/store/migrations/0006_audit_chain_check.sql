-- Review audit C1: chain selalu kanonik dan konsisten dengan site_id, sehingga satu gedung tidak
-- pernah punya dua rantai (mis. UUID huruf besar dari klien).
ALTER TABLE audit_events ADD CONSTRAINT audit_events_chain_site CHECK (
    chain = CASE WHEN site_id IS NULL THEN 'platform' ELSE 'site:' || site_id::text END
);

-- ADR-0034: enrolment yang belum selesai dilanjutkan; PROVISIONING tanpa kredensial yang melewati
-- batas waktu menjadi ABANDONED sehingga tidak lagi memakai slot atau memblokir kartu.
ALTER TABLE card_instances ADD COLUMN status_changed_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE card_instances DROP CONSTRAINT card_instances_status_check;
ALTER TABLE card_instances ADD CONSTRAINT card_instances_status_check
    CHECK (status IN ('PENDING_APPROVAL', 'PROVISIONING', 'ACTIVE', 'SUSPENDED', 'REVOKED', 'DELETED', 'REJECTED', 'ABANDONED'));

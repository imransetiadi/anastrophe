-- Masa berlaku terpanjang yang pernah diterbitkan untuk kredensial (review akhir siklus hidup M3).
-- Perpanjangan bisa memendekkan not_after bila kebijakan gedung berubah, padahal sertifikat lama yang
-- lebih panjang masih ada di tangan pemegang; denylist memakai nilai ini.
ALTER TABLE credentials ADD COLUMN max_not_after timestamptz;
UPDATE credentials SET max_not_after = not_after;

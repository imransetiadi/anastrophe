-- Kode gedung yang bisa diketik penghuni untuk enrolment kartu fisik (ADR-0044): 8 simbol Crockford
-- base32 tanpa I, L, O, U. Bukan rahasia (boleh dicetak di poster); rotasi membuat kode lama tidak berlaku.
ALTER TABLE sites ADD COLUMN join_code text UNIQUE CHECK (join_code ~ '^[0-9A-HJKMNP-TV-Z]{8}$');

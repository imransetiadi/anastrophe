# Deadlock enrolment–sapuan per jam — desain

**Status:** fokus dari ADR-0051 (JEV 0,96). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Enrolment kartu dan undangan bisa gagal 500 karena deadlock 40P01 dengan sapuan per jam: enrolment memegang kunci rantai audit gedung sambil menunggu baris instance yang dipegang sapuan, sementara sapuan menunggu kunci rantai yang sama. Iterasi ini menghilangkan siklus itu tanpa mengubah isi audit.

## Tujuan

1. **Enrolment tidak memegang kunci rantai saat menunggu baris.** Dalam `Tx.EnrollCard` dan `Tx.EnrollInvitation`, `AppendAudit` menahan event sampai akhir. Sesudah fungsi inti berhasil, termasuk sesudah pengulangan `errInstanceChanged`, semua event ditulis.
2. **Urutan penulisan.** Event diurutkan stabil per rantai audit, sehingga kunci rantai diambil dalam urutan global yang sama dan urutan di dalam satu rantai tidak berubah.
3. **Sapuan per jam** (`AbandonStaleEnrollments`) menulis audit dengan urutan rantai yang sama.
4. **Rollback tetap utuh.** Bila enrolment gagal, event yang ditahan dibuang bersama rollback.

## Non-goal

Mengubah isi, hash, atau aktor audit; mengubah jalur lain yang sudah mengunci baris sebelum audit (`transition`, `issue`, perpanjangan, hapus kartu, `DecideEnrollment`).

## Anti-goal

- Audit hilang padahal perubahannya ter-commit.
- `seq` di dalam satu rantai berubah urutan logisnya (`abandoned` sebelum `started`).

## Review Focus

1. Saat enrolment kartu menunggu baris instance yang ditahan transaksi lain, kunci advisory rantai audit gedung bebas.
2. Hal yang sama berlaku untuk enrolment undangan.
3. Event yang ditahan ditulis tepat sekali sesudah berhasil, termasuk event dari percobaan pertama sebelum pengulangan.
4. Urutan rantai saat menulis konsisten, dan urutan di dalam rantai dipertahankan.

## Diserahkan ke builder

Nama fungsi dan cara menahan event di `Tx`.

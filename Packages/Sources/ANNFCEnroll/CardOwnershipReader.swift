import ANCore

/// Membaca kartu fisik **hanya** sebagai bukti kepemilikan saat enrolment (ADR-0001). Tidak ada clone
/// UID / MIFARE Classic, dan data kartu tidak disalin. Identitas dikirim ke server lewat TLS untuk
/// dicocokkan dengan registri (HMAC per gedung, ADR-0031) dan tidak pernah disimpan atau di-log.
/// Implementasi live memakai NFCTagReaderSession (butuh iPhone dan entitlement; uji H).
public protocol CardOwnershipReader: Sendable {
    func readIdentity() async throws -> CardIdentity
}

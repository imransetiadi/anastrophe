import ANCore

/// Membaca kartu fisik **hanya** sebagai bukti kepemilikan saat enrolment
/// (ADR-0001). Tidak ada clone UID / MIFARE Classic, dan data kartu tidak
/// disalin. Implementasi live (NFCTagReaderSession) mengembalikan sidik yang
/// sudah di-hash; identitas mentah tidak pernah disimpan atau di-log.
public protocol CardOwnershipReader: Sendable {
    func readFingerprint() async throws -> CardFingerprint
}

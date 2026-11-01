import Foundation

/// Sidik kartu fisik untuk bukti kepemilikan saat enrolment (ADR-0001, ADR-0004).
/// Hanya menyimpan nilai turunan; identitas kartu mentah tidak pernah disimpan
/// atau di-log (CLAUDE.md aturan 6). Server memegang HMAC per gedung.
public struct CardFingerprint: Equatable, Sendable {
    public let digest: Data

    public init(digest: Data) {
        self.digest = digest
    }
}

extension CardFingerprint: CustomStringConvertible {
    public var description: String { "CardFingerprint(<redacted>)" }
}

import Foundation

/// Kebutuhan perpanjangan sertifikat kredensial (FR-45, SDD §5.5, ADR-0023).
public enum RenewalNeed: Equatable, Sendable {
    case none
    /// Sisa masa berlaku < 50%: perpanjang setelah tap berikutnya.
    case soon
    /// Sudah kedaluwarsa: perpanjang sebelum presentasi.
    case expired
}

public enum RenewalPolicy {
    /// Dipakai bila `not_before` tidak diketahui (record lama); default ADR-0010.
    static let defaultValidity: TimeInterval = 7 * 86_400

    public static func need(notBefore: Date?, notAfter: Date, now: Date) -> RenewalNeed {
        if now >= notAfter { return .expired }
        let lifetime = notBefore.map { notAfter.timeIntervalSince($0) } ?? defaultValidity
        return now >= notAfter.addingTimeInterval(-lifetime / 2) ? .soon : .none
    }
}

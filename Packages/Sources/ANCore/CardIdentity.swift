import Foundation

/// Identitas kartu fisik yang dibaca saat enrolment (FR-11). Hanya dikirim ke server lewat TLS untuk
/// dicocokkan dengan registri gedung, yang menyimpan HMAC per gedung (ADR-0031); app tidak pernah
/// menyimpan atau mencatatnya (CLAUDE.md aturan 6). Kartu fisik hanya bukti kepemilikan (ADR-0001).
public struct CardIdentity: Equatable, Sendable {
    public enum Technology: String, Sendable, CaseIterable {
        case iso14443a, iso15693, felica, iso7816

        /// Panjang identitas yang sah, sama dengan validasi server.
        func accepts(length: Int) -> Bool {
            switch self {
            case .iso14443a: [4, 7, 10].contains(length)
            case .iso15693, .felica: length == 8
            case .iso7816: (1...32).contains(length)
            }
        }
    }

    public let technology: Technology
    public let identifier: Data

    public init?(technology: Technology, identifier: Data) {
        guard technology.accepts(length: identifier.count) else { return nil }
        self.technology = technology
        self.identifier = identifier
    }

    /// `<tech>:<hex>`, mis. `iso14443a:04a1b2c3d4e5f6`.
    public init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let technology = Technology(rawValue: String(parts[0])),
              let identifier = Data(hexString: String(parts[1]))
        else { return nil }
        self.init(technology: technology, identifier: identifier)
    }

    /// Hex huruf kecil untuk body permintaan enrolment.
    public var hex: String { identifier.hexString }
}

/// Teks dan dump tidak pernah memuat identifier, agar tidak ikut tercatat (aturan 6).
extension CardIdentity: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "CardIdentity(\(technology.rawValue), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

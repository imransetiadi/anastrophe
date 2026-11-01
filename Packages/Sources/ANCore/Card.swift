import Foundation

/// Status kartu yang terlihat pengguna (FR-38), ditambah "Perlu dipindahkan" (SDD §5.3).
public enum CardStatus: String, Codable, Sendable {
    case active
    case pendingApproval
    case suspended
    case needsRenewal
    case revoked
    case needsTransfer
}

extension ChannelKind: CodingKeyRepresentable {}

/// Kartu akses gedung di perangkat. Batas 8 dihitung per kartu, bukan per
/// kredensial (SDD §4.2). Tidak memuat identitas kartu fisik (ADR-0001).
public struct Card: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var siteName: String
    public var zones: [String]
    public var status: CardStatus
    /// Kanal → `cred_id` (satu kredensial per kanal).
    public var credentials: [ChannelKind: Data]
    public var notAfter: Date?

    public init(id: UUID, name: String, siteName: String, zones: [String], status: CardStatus, credentials: [ChannelKind: Data], notAfter: Date?) {
        self.id = id
        self.name = name
        self.siteName = siteName
        self.zones = zones
        self.status = status
        self.credentials = credentials
        self.notAfter = notAfter
    }
}

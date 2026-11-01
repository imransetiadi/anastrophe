import Foundation

/// Satu transaksi dengan reader yang dicatat di perangkat (FR-30). Tanpa lokasi atau identitas
/// reader; hanya kartu lokal, waktu, kanal, dan hasil.
public struct TapEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let date: Date
    public let channel: ChannelKind
    public let granted: Bool
    public let denyReason: DenyReason?

    public init(id: UUID = UUID(), cardID: UUID, date: Date, channel: ChannelKind, granted: Bool, denyReason: DenyReason?) {
        self.id = id
        self.cardID = cardID
        self.date = date
        self.channel = channel
        self.granted = granted
        self.denyReason = denyReason
    }
}

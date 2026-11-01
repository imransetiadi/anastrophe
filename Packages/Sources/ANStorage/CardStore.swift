import ANCore
import Foundation

/// Metadata kartu lokal, di balik protokol agar bisa di-mock.
public protocol CardStore: Sendable {
    /// Urut menurut waktu penambahan.
    func all() async throws -> [Card]
    /// `ANError.cardLimitReached` bila perangkat sudah memegang 8 kartu (FR-15).
    func add(_ card: Card) async throws
    func update(_ card: Card) async throws
    func remove(id: UUID) async throws
}

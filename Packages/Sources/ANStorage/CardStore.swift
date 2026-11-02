import ANCore
import Foundation

/// Metadata kartu lokal, di balik protokol agar bisa di-mock.
public protocol CardStore: Sendable {
    /// Urut menurut waktu penambahan. Mengembalikan semua kartu atau gagal, tidak pernah daftar
    /// sebagian: pembersihan riwayat tap mengandalkan daftar ini lengkap.
    func all() async throws -> [Card]
    /// `ANError.cardLimitReached` bila perangkat sudah memegang 8 kartu (FR-15).
    func add(_ card: Card) async throws
    func update(_ card: Card) async throws
    func remove(id: UUID) async throws
    /// Pembaruan terarah: `mutate` diterapkan pada nilai terbaru yang tersimpan dan hanya disimpan bila
    /// mengembalikan true, sehingga penulis lain tidak tertimpa salinan basi (review akhir siklus hidup M4).
    func update(id: UUID, _ mutate: @Sendable (inout Card) -> Bool) async throws -> Bool
}

extension CardStore {
    /// Bawaan untuk store sederhana (baca lalu tulis, tidak atomik); `SwiftDataCardStore` menimpanya
    /// dengan versi atomik di dalam actor-nya.
    public func update(id: UUID, _ mutate: @Sendable (inout Card) -> Bool) async throws -> Bool {
        guard var card = try await all().first(where: { $0.id == id }) else { throw ANError.invalidData }
        guard mutate(&card) else { return false }
        try await update(card)
        return true
    }
}

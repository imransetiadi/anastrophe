import ANCore
import ANStorage
import Foundation
import Observation

/// Petunjuk perpanjangan di detail kartu (TC-DEV-10).
public enum RenewalNotice: Equatable, Sendable {
    /// Diperbarui otomatis saat kartu dipakai berikutnya.
    case renewsOnNextUse
    /// Perangkat offline: perlu terhubung ke internet agar bisa diperbarui.
    case needsInternet
}

/// Daftar kartu di tab Kunci. Saat dimuat, kartu yang kuncinya hilang ditandai
/// "Perlu dipindahkan" (SDD §5.3).
@MainActor
@Observable
public final class KeysViewModel {
    public private(set) var cards: [Card] = []
    public private(set) var availability: [ChannelKind: ChannelAvailability] = [:]
    public private(set) var isLoading = true
    public private(set) var isOnline = true
    /// Riwayat tap 30 hari per kartu (FR-30), terbaru dulu.
    private var histories: [Card.ID: [TapEntry]] = [:]
    static let historyRetention: TimeInterval = 30 * 86_400
    /// Kartu yang record-nya punya backend penerbit (dibaca sekali saat dimuat, bukan per render).
    private var renewable: Set<Card.ID> = []
    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var canAddCard: Bool { CardLimit.canAddCard(currentCount: cards.count) }

    public func load() async {
        let stored = (try? await services.cards.all()) ?? []
        let reconciled = RestoreCheck.reconcile(stored, keys: services.keys).map(expiryFromRecord)
        for (old, new) in zip(stored, reconciled) where old != new {
            try? await services.cards.update(new)
        }
        cards = reconciled
        renewable = Set(reconciled.filter { card in
            card.credentials.values.contains { (try? services.records.record(for: $0))?.renewalURL != nil }
        }.map(\.id))
        availability = await services.availability()
        isOnline = services.connectivity.isOnline
        isLoading = false  // daftar tampil dulu (NFR-P03); riwayat menyusul
        let cutoff = Date.now.addingTimeInterval(-Self.historyRetention)
        try? await services.tapHistory.purge(before: cutoff)
        // Riwayat kartu yang sudah tidak ada (mis. hapus yang terputus) dibersihkan. Daftar dibaca ulang
        // tepat sebelum menghapus agar kartu yang ditambahkan selama load() ini tidak kehilangan riwayat;
        // galat baca berarti tidak ada yang dihapus.
        if let current = try? await services.cards.all() {
            try? await services.tapHistory.removeAll(except: Set(current.map(\.id)))
        }
        var loaded: [Card.ID: [TapEntry]] = [:]
        for card in reconciled {
            loaded[card.id] = (try? await services.tapHistory.entries(for: card.id, since: cutoff)) ?? []
        }
        histories = loaded
    }

    /// Record kredensial adalah sumber kebenaran masa berlaku (perpanjangan memperbarui record
    /// lebih dulu); kartu di daftar disesuaikan bila berbeda.
    private func expiryFromRecord(_ card: Card) -> Card {
        guard let record = card.credentials.values.lazy.compactMap({ try? self.services.records.record(for: $0) }).first,
              record.notAfter != card.notAfter
        else { return card }
        var updated = card
        updated.notAfter = record.notAfter
        return updated
    }

    /// Memuat ulang ketersediaan kanal (mis. setelah Bluetooth dinyalakan atau izin diberikan).
    public func refreshAvailability() async {
        availability = await services.availability()
    }

    /// Hanya untuk kartu yang bisa dipakai dan perlu diperbarui (sisa < 24 jam atau sudah lewat).
    public func renewalNotice(for card: Card, now: Date = .now) -> RenewalNotice? {
        guard card.displayStatus(now: now) == .needsRenewal, presentability(of: card).canPresent else { return nil }
        return isOnline ? .renewsOnNextUse : .needsInternet
    }

    public func history(for card: Card) -> [TapEntry] {
        histories[card.id] ?? []
    }

    public func presentability(of card: Card) -> Presentability {
        .evaluate(card, availability: availability, renewable: renewable.contains(card.id))
    }
}

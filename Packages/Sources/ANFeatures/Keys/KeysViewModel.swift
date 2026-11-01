import ANCore
import ANStorage
import Observation

/// Daftar kartu di tab Kunci. Saat dimuat, kartu yang kuncinya hilang ditandai
/// "Perlu dipindahkan" (SDD §5.3).
@MainActor
@Observable
public final class KeysViewModel {
    public private(set) var cards: [Card] = []
    public private(set) var availability: [ChannelKind: ChannelAvailability] = [:]
    public private(set) var isLoading = true
    /// Kartu yang record-nya punya backend penerbit (dibaca sekali saat dimuat, bukan per render).
    private var renewable: Set<Card.ID> = []
    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var canAddCard: Bool { CardLimit.canAddCard(currentCount: cards.count) }

    public func load() async {
        let stored = (try? await services.cards.all()) ?? []
        let reconciled = RestoreCheck.reconcile(stored, keys: services.keys)
        for (old, new) in zip(stored, reconciled) where old != new {
            try? await services.cards.update(new)
        }
        cards = reconciled
        renewable = Set(reconciled.filter { card in
            card.credentials.values.contains { (try? services.records.record(for: $0))?.renewalURL != nil }
        }.map(\.id))
        availability = await services.availability()
        isLoading = false
    }

    /// Memuat ulang ketersediaan kanal (mis. setelah Bluetooth dinyalakan atau izin diberikan).
    public func refreshAvailability() async {
        availability = await services.availability()
    }

    public func presentability(of card: Card) -> Presentability {
        .evaluate(card, availability: availability, renewable: renewable.contains(card.id))
    }
}

import ANCore
import ANStorage
import Foundation

/// Mencatat transaksi dengan reader (diizinkan/ditolak) ke riwayat tap lokal (FR-30), untuk
/// launcher mana pun. Batal, timeout, dan reader di luar jangkauan bukan transaksi.
@MainActor
final class RecordingLauncher: PresentationLaunching {
    private let base: any PresentationLaunching
    private let history: any TapHistoryStore
    private let now: @Sendable () -> Date

    init(base: any PresentationLaunching, history: any TapHistoryStore, now: @escaping @Sendable () -> Date = { .now }) {
        self.base = base
        self.history = history
        self.now = now
    }

    func start(card: Card, channel: ChannelKind) async -> AsyncStream<PresentmentEvent> {
        let upstream = await base.start(card: card, channel: channel)
        let history = history, now = now
        return AsyncStream { continuation in
            let forwarding = Task {
                for await event in upstream {
                    if let entry = Self.entry(for: event, cardID: card.id, channel: channel, at: now()) {
                        try? await history.append(entry)
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    func cancel() async {
        await base.cancel()
    }

    nonisolated static func entry(for event: PresentmentEvent, cardID: UUID, channel: ChannelKind, at date: Date) -> TapEntry? {
        switch event {
        case .granted:
            TapEntry(cardID: cardID, date: date, channel: channel, granted: true, denyReason: nil)
        case .denied(let reason):
            TapEntry(cardID: cardID, date: date, channel: channel, granted: false, denyReason: reason)
        default:
            nil
        }
    }
}

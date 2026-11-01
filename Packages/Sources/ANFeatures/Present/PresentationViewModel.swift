import ANCore
import Observation

/// Mengubah aliran `PresentmentEvent` dari coordinator kanal menjadi fase UI.
@MainActor
@Observable
public final class PresentationViewModel {
    public enum Phase: Equatable, Sendable {
        case waiting
        case coolingDown(seconds: Int)
        case readerFound
        case exchanging
        case granted
        case denied(DenyReason)
        case timedOut
        case cancelled
        /// Kanal tidak bisa dipakai (mis. Bluetooth mati/izin ditolak); lembar memberi panduan.
        case unavailable(ChannelAvailability)
        case readerOutOfRange
    }

    public private(set) var phase: Phase = .waiting
    private let events: AsyncStream<PresentmentEvent>

    public init(events: AsyncStream<PresentmentEvent>) {
        self.events = events
    }

    public var isFinished: Bool {
        switch phase {
        case .granted, .denied, .timedOut, .cancelled, .unavailable, .readerOutOfRange: true
        case .waiting, .coolingDown, .readerFound, .exchanging: false
        }
    }

    /// Selesai saat aliran event berakhir. Aliran yang berakhir tanpa hasil dianggap batal.
    public func start() async {
        for await event in events {
            phase = Self.phase(for: event)
        }
        if !isFinished { phase = .cancelled }
    }

    static func phase(for event: PresentmentEvent) -> Phase {
        switch event {
        case .coolingDown(let seconds): .coolingDown(seconds: seconds)
        case .waitingForReader: .waiting
        case .readerFound: .readerFound
        case .exchanging: .exchanging
        case .granted: .granted
        case .denied(let reason): .denied(reason)
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case .unavailable(let availability): .unavailable(availability)
        case .readerOutOfRange: .readerOutOfRange
        }
    }
}

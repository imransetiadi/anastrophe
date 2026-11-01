#if os(iOS)
@preconcurrency import CoreNFC

extension NFCPresentmentIntentAssertion: PresentmentIntent {}

/// Assertion live (O-A05). Dilepas saat referensinya dilepas.
public struct LivePresentmentIntentProvider: PresentmentIntentProvider {
    public init() {}

    public func acquire() async throws -> any PresentmentIntent {
        try await NFCPresentmentIntentAssertion.acquire()
    }
}

/// Adapter `CardSession`. Hanya dibuat oleh `HCEPresentmentCoordinator` setelah
/// gating lolos (CLAUDE.md aturan 3). Pemanggilan metode diserialkan oleh coordinator,
/// sedangkan `eventStream` diiterasi di Task terpisah secara bersamaan, sesuai desain CoreNFC.
public final class LiveCardEmulationSession: CardEmulationSession, @unchecked Sendable {
    private let session: CardSession
    public let events: AsyncStream<CardEmulationEvent>

    public init() async throws {
        let session = try await CardSession()
        self.session = session
        // CoreNFC mendesain `eventStream` untuk dikonsumsi bersamaan dengan pemanggilan metode
        // sesi (pola contoh Apple); compiler tidak bisa membuktikannya untuk tipe non-Sendable.
        nonisolated(unsafe) let stream = session.eventStream
        events = AsyncStream { continuation in
            let task = Task {
                do {
                    for try await event in stream { continuation.yield(Self.map(event)) }
                } catch {
                    continuation.yield(.invalidated(.other))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func setAlertMessage(_ message: String) async {
        session.alertMessage = message
    }

    public func startEmulation() async throws {
        try await session.startEmulation()
    }

    public func stopEmulation(success: Bool) async {
        await session.stopEmulation(status: success ? .success : .failure)
    }

    public func invalidate() async {
        session.invalidate()
    }

    private static func map(_ event: CardSession.Event) -> CardEmulationEvent {
        switch event {
        case .sessionStarted:
            return .sessionStarted
        case .readerDetected:
            return .readerDetected
        case .readerDeselected:
            return .readerDeselected
        case .received(let apdu):
            return .received(ReceivedAPDU(payload: apdu.payload) { response throws(CardEmulationError) in
                do {
                    try await apdu.respond(response: response)
                } catch CardSession.Error.transmissionError {
                    throw .transmission
                } catch {
                    throw .other
                }
            })
        case .sessionInvalidated(let reason):
            let error: CardEmulationError = switch reason {
            case .maxSessionDurationReached: .timeLimit
            case .transmissionError: .transmission
            default: .other
            }
            return .invalidated(error)
        @unknown default:
            return .invalidated(.other)
        }
    }
}
#endif

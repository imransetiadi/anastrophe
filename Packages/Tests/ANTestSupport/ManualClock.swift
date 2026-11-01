import Foundation

/// Clock yang hanya maju lewat `advance(by:)`, agar timeout & cooldown teruji tanpa menunggu.
public final class ManualClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol, Hashable {
        public var offset: Duration

        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: (deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = [:]
    private var cancelledEarly: Set<UUID> = []

    public init() {}

    public var now: Instant { lock.withLock { current } }
    public var minimumResolution: Duration { .zero }
    public var sleeperCount: Int { lock.withLock { sleepers.count } }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let immediate: Result<Void, any Error>? = lock.withLock {
                    if cancelledEarly.remove(id) != nil { return .failure(CancellationError()) }
                    if deadline <= current { return .success(()) }
                    sleepers[id] = (deadline, continuation)
                    return nil
                }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
                if let sleeper = sleepers.removeValue(forKey: id) { return sleeper.continuation }
                cancelledEarly.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    public func advance(by duration: Duration) {
        let due: [CheckedContinuation<Void, any Error>] = lock.withLock {
            current = current.advanced(by: duration)
            let ready = sleepers.filter { $0.value.deadline <= current }
            ready.keys.forEach { sleepers.removeValue(forKey: $0) }
            return ready.map(\.value.continuation)
        }
        due.forEach { $0.resume() }
    }

    /// Menunggu (maks ±10 dtk waktu nyata, untuk CI lambat) sampai ada `count` task yang tidur.
    public func waitForSleepers(_ count: Int) async {
        for _ in 0..<10_000 where sleeperCount < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

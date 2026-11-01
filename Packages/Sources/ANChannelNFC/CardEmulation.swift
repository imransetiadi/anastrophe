import Foundation

/// Kegagalan sesi emulasi kartu.
public enum CardEmulationError: Error, Equatable, Sendable {
    case transmission
    /// Sistem mengakhiri sesi karena batas durasi.
    case timeLimit
    case other
}

/// APDU dari reader beserta cara menjawabnya. Di CoreNFC jawaban dikirim lewat
/// objek APDU itu sendiri, sehingga sesi tidak perlu menyimpan "APDU terakhir".
public struct ReceivedAPDU: Sendable {
    public let payload: Data
    public let respond: @Sendable (Data) async throws(CardEmulationError) -> Void

    public init(payload: Data, respond: @escaping @Sendable (Data) async throws(CardEmulationError) -> Void) {
        self.payload = payload
        self.respond = respond
    }
}

public enum CardEmulationEvent: Sendable {
    case sessionStarted
    case readerDetected
    case received(ReceivedAPDU)
    case readerDeselected
    case invalidated(CardEmulationError)
}

/// Sesi emulasi kartu (live: `CardSession`), di balik protokol agar bisa di-mock.
public protocol CardEmulationSession: AnyObject, Sendable {
    var events: AsyncStream<CardEmulationEvent> { get }
    func setAlertMessage(_ message: String) async
    func startEmulation() async throws
    func stopEmulation(success: Bool) async
    func invalidate() async
}

/// Presentment intent assertion yang sedang dipegang. Dilepas dengan melepas referensinya.
public protocol PresentmentIntent: AnyObject, Sendable {}

public protocol PresentmentIntentProvider: Sendable {
    func acquire() async throws -> any PresentmentIntent
}

import ANCore
import Foundation

/// Reader yang terlihat saat pemindaian.
public struct BLEReaderAdvertisement: Equatable, Sendable {
    public let id: UUID
    /// `group_id` 8 B dari data iklan service ANP (bukan data pengguna).
    public let groupID: Data
    public let rssi: Int

    public init(id: UUID, groupID: Data, rssi: Int) {
        self.id = id
        self.groupID = groupID
        self.rssi = rssi
    }
}

/// Koneksi GATT ke satu reader. Link BLE dianggap tidak tepercaya; keamanan dari ANP/1.
public protocol BLELink: Sendable {
    /// Ukuran frame maksimum per tulis (`maximumWriteValueLength(for: .withResponse)`).
    var mtu: Int { get }
    /// Frame reader → ponsel (indikasi `ANP-Response`).
    var commands: AsyncThrowingStream<Data, any Error> { get }
    /// Frame ponsel → reader (`ANP-Control`, write with response).
    func write(_ frame: Data) async throws
    func disconnect() async
}

/// Central Core Bluetooth, di balik protokol agar bisa di-mock.
public protocol BLECentral: Sendable {
    /// Memindai sampai `window` menyatakan berhenti (early exit, ADR-0019).
    func scan(_ window: ScanWindow) async throws -> [BLEReaderAdvertisement]
    /// Terhubung dan menyiapkan GATT ANP. Harus menghormati pembatalan task.
    func connect(_ id: UUID) async throws -> any BLELink
}

/// Kapan pemindaian berhenti: segera setelah reader pertama memenuhi ambang RSSI
/// ditambah jeda singkat untuk membandingkan RSSI, maksimal `maximum` (ADR-0019).
public struct ScanWindow: Equatable, Sendable {
    public let threshold: Int
    public let settle: Duration
    public let maximum: Duration
    private var firstQualifiedAt: Duration?

    public init(threshold: Int, settle: Duration = .milliseconds(300), maximum: Duration = .seconds(5)) {
        self.threshold = threshold
        self.settle = settle
        self.maximum = maximum
    }

    public mutating func record(rssi: Int, at elapsed: Duration) {
        if rssi >= threshold, firstQualifiedAt == nil { firstQualifiedAt = elapsed }
    }

    public func shouldStop(elapsed: Duration) -> Bool {
        if elapsed >= maximum { return true }
        guard let firstQualifiedAt else { return false }
        return elapsed >= firstQualifiedAt + settle
    }
}

public enum BLEError: Error, Equatable, Sendable {
    case poweredOff
    case unauthorized
    case unsupported
    case readerNotFound
    case disconnected
    /// Service/karakteristik ANP tidak ditemukan di peripheral.
    case gattMismatch
    case timeout

    /// Padanan ketersediaan kanal untuk panduan pengguna (FR-82); `nil` bila bukan soal kanal.
    public var availability: ChannelAvailability? {
        switch self {
        case .poweredOff: .bluetoothOff
        case .unauthorized: .bluetoothUnauthorized
        case .unsupported: .unsupportedDevice
        case .readerNotFound, .disconnected, .gattMismatch, .timeout: nil
        }
    }
}

/// Hanya reader dengan RSSI tertinggi di atas ambang yang diproses (FR-83).
public enum BLEReaderSelector {
    public static let defaultThreshold = -55

    public static func choose(_ advertisements: [BLEReaderAdvertisement], threshold: Int = defaultThreshold) -> BLEReaderAdvertisement? {
        advertisements.filter { $0.rssi >= threshold }.max { $0.rssi < $1.rssi }
    }
}

/// Maksimal 1 transaksi per 3 dtk per reader (SDD §6.3).
public struct ReaderRateLimiter<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration {
    public static var interval: Duration { .seconds(3) }
    private var lastStart: [UUID: Instant] = [:]

    public init() {}

    /// Sisa jeda sebelum reader boleh dipakai lagi; `.zero` bila boleh sekarang.
    public func remaining(_ readerID: UUID, at now: Instant) -> Duration {
        guard let last = lastStart[readerID] else { return .zero }
        return max(.zero, Self.interval - last.duration(to: now))
    }

    /// Mencatat transaksi bila diizinkan.
    public mutating func allow(_ readerID: UUID, at now: Instant) -> Bool {
        guard remaining(readerID, at: now) == .zero else { return false }
        lastStart[readerID] = now
        return true
    }
}

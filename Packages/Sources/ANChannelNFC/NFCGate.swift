import ANCore
import Foundation

/// Kapabilitas sistem NFC, di balik protokol agar bisa di-mock (QA §2).
public protocol NFCCapabilities: Sendable {
    var readingAvailable: Bool { get }
    var cardSessionSupported: Bool { get }
    func isCardSessionEligible() async -> Bool
    func isCredentialSessionEligible() async -> Bool
}

/// Gating kelayakan kanal N (SDD §5.4). `CardSession()` tanpa entitlement
/// memicu `fatalError` (O-A02), jadi sesi hanya boleh dibuat lewat
/// `withEligibleSession` (CLAUDE.md aturan 3).
public struct NFCGate: Sendable {
    private let capabilities: any NFCCapabilities
    private let entitled: Bool

    /// `entitled` = build ini membawa entitlement emulasi (`AN_NFC_EMULATION`). Tanpa itu
    /// API `CardSession`/`CredentialSession` tidak pernah disentuh (TC-ELG-03).
    public init(capabilities: any NFCCapabilities, entitled: Bool) {
        self.capabilities = capabilities
        self.entitled = entitled
    }

    public func availability(_ kind: ChannelKind, config: RemoteConfig) async -> ChannelAvailability {
        guard config.enabledChannels.contains(kind) else { return .regionBlocked }
        if kind == .nfcHCE || kind == .nfcSE, !entitled { return .entitlementMissing }
        switch kind {
        case .nfcHCE:
            guard capabilities.readingAvailable, capabilities.cardSessionSupported else { return .unsupportedDevice }
            guard await capabilities.isCardSessionEligible() else { return .notEligible }
        case .nfcSE:
            guard await capabilities.isCredentialSessionEligible() else { return .notEligible }
        case .ble, .wallet:
            return .unsupportedDevice
        }
        return .available
    }

    public func withEligibleSession<T>(
        _ kind: ChannelKind,
        config: RemoteConfig,
        _ makeSession: () async throws -> T
    ) async throws -> T {
        let availability = await availability(kind, config: config)
        guard availability == .available else { throw ANError.channelUnavailable(availability) }
        return try await makeSession()
    }
}

/// Batas presentment (CLAUDE.md aturan 4, O-A05, O-A21).
public enum PresentmentLimits {
    /// Jeda sebelum assertion HCE boleh diambil ulang (O-A05).
    public static let hceCooldownSeconds: TimeInterval = 15
    /// Batas emulasi HCE dengan hitung mundur (FR-22, O-A03).
    public static let hceEmulationSeconds: TimeInterval = 60
    public static let seAssertionsPerWindow = 2
    public static let seWindowSeconds: TimeInterval = 80
}

/// Maksimum 2 assertion SE per jendela geser 80 dtk.
public struct SEAssertionBudget: Sendable {
    private var acquiredAt: [TimeInterval] = []

    public init() {}

    public mutating func tryAcquire(now: TimeInterval) -> Bool {
        acquiredAt.removeAll { now - $0 >= PresentmentLimits.seWindowSeconds }
        guard acquiredAt.count < PresentmentLimits.seAssertionsPerWindow else { return false }
        acquiredAt.append(now)
        return true
    }
}

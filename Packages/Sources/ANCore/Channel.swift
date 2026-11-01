// Model kanal (SDD §4.1). Istilah mengikuti GLOSSARY.md.

/// Kanal kredensial: W (Apple Wallet), N-SE, N-HCE, B (BLE).
public enum ChannelKind: String, Codable, Sendable, CaseIterable {
    case wallet  // W
    case nfcSE   // N-SE
    case nfcHCE  // N-HCE
    case ble     // B

    /// Urutan prioritas W > N-SE > N-HCE > B (SDD §4.2).
    public static let priorityOrder: [ChannelKind] = [.wallet, .nfcSE, .nfcHCE, .ble]
}

public enum ChannelAvailability: Equatable, Sendable {
    case available
    case unsupportedDevice
    case notEligible
    case regionBlocked
    case entitlementMissing
    case bluetoothOff
    case bluetoothUnauthorized
    case programNotEnabled
}

public enum DenyReason: String, Codable, Sendable {
    case expired, suspended, revoked, outsideSchedule, zoneNotAllowed, unknown

    /// Kode alasan `F2` di RESULT ANP/1 (SDD §7.4).
    public init(anp1Code: UInt8) {
        self = switch anp1Code {
        case 0x01: .expired
        case 0x02: .suspended
        case 0x03: .revoked
        case 0x04: .outsideSchedule
        case 0x05: .zoneNotAllowed
        default: .unknown
        }
    }
}

public enum PresentmentEvent: Equatable, Sendable {
    /// Assertion ditolak sistem; menunggu cooldown sebelum mencoba lagi (TC-PRSN-05).
    case coolingDown(seconds: Int)
    case waitingForReader
    case readerFound(name: String?)
    case exchanging
    case granted
    case denied(reason: DenyReason)
    case timedOut
    case cancelled
    /// Kanal tidak bisa dipakai (mis. Bluetooth mati atau izin ditolak); UI memberi panduan (FR-82).
    case unavailable(ChannelAvailability)
    /// Tidak ada reader B yang cukup dekat (RSSI di bawah ambang) selama pemindaian (TC-PRSB-05).
    case readerOutOfRange
}

/// Konfigurasi dari server (`/config`, FR-04).
public struct RemoteConfig: Codable, Equatable, Sendable {
    public var enabledChannels: Set<ChannelKind>
    public var walletProgramEnabled: Bool

    public init(enabledChannels: Set<ChannelKind>, walletProgramEnabled: Bool = false) {
        self.enabledChannels = enabledChannels
        self.walletProgramEnabled = walletProgramEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabledChannels = "enabled_channels"
        case walletProgramEnabled = "wallet_program_enabled"
    }
}

public enum ChannelSelector {
    /// Kanal dipakai bila diizinkan kebijakan gedung dan tersedia secara lokal (SDD §4.2).
    /// Izin server sudah tercermin di `availability` (`.regionBlocked`).
    public static func preferred(
        allowedBySite: Set<ChannelKind>,
        availability: [ChannelKind: ChannelAvailability]
    ) -> ChannelKind? {
        ChannelKind.priorityOrder.first { kind in
            allowedBySite.contains(kind) && availability[kind] == .available
        }
    }
}

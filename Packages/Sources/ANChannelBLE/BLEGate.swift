import ANCore

/// Otorisasi Bluetooth, dipisah dari `CBManagerAuthorization` agar bisa diuji.
public enum BLEAuthorization: Sendable {
    case notDetermined, restricted, denied, allowed
}

/// Ketersediaan kanal B (SDD §5.4). Hanya foreground Tap di R1 (ADR-0012).
public enum BLEGate {
    public static func availability(authorization: BLEAuthorization, poweredOn: Bool, config: RemoteConfig) -> ChannelAvailability {
        guard config.enabledChannels.contains(.ble) else { return .regionBlocked }
        switch authorization {
        case .denied, .restricted: return .bluetoothUnauthorized
        case .notDetermined, .allowed: break
        }
        // Sebelum izin diminta, status radio belum bisa dibaca; anggap tersedia
        // agar app sempat memunculkan prompt izin Bluetooth.
        return poweredOn || authorization == .notDetermined ? .available : .bluetoothOff
    }
}

#if canImport(CoreBluetooth)
import CoreBluetooth

extension BLEAuthorization {
    public static var current: BLEAuthorization {
        switch CBManager.authorization {
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
#endif

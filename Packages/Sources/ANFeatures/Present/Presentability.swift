import ANCore
import Foundation

/// Apakah kartu bisa dipresentasikan sekarang, dan lewat kanal apa (FR-05, FR-38).
public enum Presentability: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case needsTransfer
        case suspended
        case revoked
        case pendingApproval
        /// Sertifikat lokal sudah lewat masa berlaku dan belum diperbarui (ADR-0010).
        case expired
        case bluetoothOff
        case bluetoothUnauthorized
        /// Tidak ada kanal yang diizinkan gedung sekaligus tersedia di perangkat/wilayah ini.
        case noChannel
    }

    case available(ChannelKind)
    case unavailable(Reason)

    public var canPresent: Bool {
        if case .available = self { true } else { false }
    }

    public static func evaluate(_ card: Card, availability: [ChannelKind: ChannelAvailability], now: Date = .now) -> Presentability {
        switch card.status {
        case .needsTransfer: return .unavailable(.needsTransfer)
        case .suspended: return .unavailable(.suspended)
        case .revoked: return .unavailable(.revoked)
        case .pendingApproval: return .unavailable(.pendingApproval)
        case .active, .needsRenewal: break  // sertifikat yang perlu diperbarui masih berlaku
        }
        if let notAfter = card.notAfter, notAfter < now { return .unavailable(.expired) }
        // R1 hanya mempresentasikan dari app lewat N-HCE dan B; W dipakai lewat Wallet sistem.
        let inApp = Set(card.credentials.keys).intersection([.nfcHCE, .ble])
        guard let channel = ChannelSelector.preferred(allowedBySite: inApp, availability: availability) else {
            // Beri alasan yang bisa ditindaklanjuti pengguna bila kanal B terhalang Bluetooth (FR-82).
            if inApp.contains(.ble) {
                switch availability[.ble] {
                case .bluetoothOff?: return .unavailable(.bluetoothOff)
                case .bluetoothUnauthorized?: return .unavailable(.bluetoothUnauthorized)
                default: break
                }
            }
            return .unavailable(.noChannel)
        }
        return .available(channel)
    }
}

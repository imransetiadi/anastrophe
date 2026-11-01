import ANCore
import Foundation

/// Deteksi restore saat launch (SDD §5.3, FR-40, FR-44): kartu yang metadatanya
/// ada tetapi kunci in-app-nya hilang ditandai "Perlu dipindahkan".
public enum RestoreCheck {
    /// Kanal yang kuncinya disimpan app di Secure Enclave. N-SE di applet, W di Wallet.
    static let inAppKeyChannels: Set<ChannelKind> = [.nfcHCE, .ble]

    public static func reconcile(_ cards: [Card], keys: any CredentialKeyStore) -> [Card] {
        cards.map { card in
            // Status pemblokir dari server (ditangguhkan, menunggu persetujuan, dicabut)
            // didahulukan: memindahkan kartu tidak menyelesaikannya.
            guard [.active, .needsRenewal, .needsTransfer].contains(card.status) else { return card }
            let inApp = card.credentials.filter { inAppKeyChannels.contains($0.key) }.map(\.value)
            // Keychain yang tidak bisa dibaca (mis. perangkat terkunci) bukan bukti kunci hilang.
            guard let present = try? inApp.allSatisfy({ try keys.hasKey(for: $0) }) else { return card }
            var updated = card
            if !present {
                updated.status = .needsTransfer
            } else if card.status == .needsTransfer {
                updated.status = .active  // kunci kembali terbaca
            }
            return updated
        }
    }
}

import ANCore
import ANNetworking
import ANStorage
import Foundation

/// Menyegarkan status kartu dari server dengan token baca status (FR-38, ADR-0037). Tidak ada tanda
/// tangan kunci kredensial, jadi tidak ada prompt; presentasi tidak menunggu ini dan tetap berjalan
/// offline dengan status terakhir (FR-25).
@MainActor
final class CardStatusRefresher {
    /// Status jarang berubah; batas ini mencegah permintaan beruntun saat pengguna berpindah app.
    static let minimumInterval: TimeInterval = 60

    private let cards: any CardStore
    private let records: any CredentialRecordStore
    private let tokens: any StatusTokenStore
    private var lastRefresh: Date?

    init(cards: any CardStore, records: any CredentialRecordStore, tokens: any StatusTokenStore) {
        self.cards = cards
        self.records = records
        self.tokens = tokens
    }

    /// Mengembalikan true bila ada kartu yang statusnya berubah. Galat jaringan dan jawaban server
    /// yang tidak dikenali membiarkan status lokal apa adanya.
    func refresh(now: Date = .now, transport: any HTTPTransport = URLSession.shared) async -> Bool {
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < Self.minimumInterval { return false }
        lastRefresh = now
        guard let all = try? await cards.all() else { return false }
        var changed = false
        for card in all {
            guard let (backend, serverCardID) = server(of: card),
                  let token = try? tokens.token(forCard: serverCardID),
                  let status = try? await APIClient(baseURL: backend, transport: transport).cardStatus(cardID: serverCardID, token: token)
            else { continue }
            // Baca ulang: kartu bisa berubah atau terhapus selama permintaan berjalan.
            guard var current = try? await cards.all().first(where: { $0.id == card.id }),
                  let next = Self.localStatus(server: status, current: current.status)
            else { continue }
            current.status = next
            if (try? await cards.update(current)) != nil { changed = true }
        }
        return changed
    }

    /// Status lokal baru, atau nil bila tidak berubah. Dicabut bersifat final dan menang atas apa pun.
    /// Kunci lokal yang hilang ("Perlu dipindahkan") tidak ditimpa penangguhan maupun pemulihan, dan
    /// ACTIVE hanya memulihkan kartu yang ditangguhkan.
    static func localStatus(server: String, current: CardStatus) -> CardStatus? {
        switch (server, current) {
        case (_, .revoked): nil
        case ("REVOKED", _), ("DELETED", _): .revoked
        case (_, .needsTransfer): nil
        case ("SUSPENDED", .suspended): nil
        case ("SUSPENDED", _): .suspended
        case ("ACTIVE", .suspended): .active
        default: nil
        }
    }

    /// Backend dan id card instance server dari record kredensial kartu yang punya keduanya.
    private func server(of card: Card) -> (URL, String)? {
        for credentialID in card.credentials.values.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            if let record = try? records.record(for: credentialID), let backend = record.renewalURL, let id = record.serverCardID {
                return (backend, id)
            }
        }
        return nil
    }
}

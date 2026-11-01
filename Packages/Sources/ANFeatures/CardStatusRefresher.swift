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
    /// Jam monotonik (detik sejak boot): mengubah jam dinding tidak menahan penyegaran (review M6).
    private let uptime: @Sendable () -> TimeInterval
    private var lastRefresh: TimeInterval?

    init(cards: any CardStore, records: any CredentialRecordStore, tokens: any StatusTokenStore,
         uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.cards = cards
        self.records = records
        self.tokens = tokens
        self.uptime = uptime
    }

    /// Mengembalikan true bila ada kartu yang statusnya berubah. Galat jaringan dan jawaban server
    /// yang tidak dikenali membiarkan status lokal apa adanya.
    func refresh(transport: any HTTPTransport = URLSession.shared) async -> Bool {
        let now = uptime()
        if let lastRefresh, now - lastRefresh < Self.minimumInterval { return false }
        lastRefresh = now
        guard let all = try? await cards.all() else { return false }
        var changed = false
        for card in all where card.status != .revoked {  // Dicabut bersifat final (review M6)
            guard let (backend, serverCardID) = server(of: card),
                  let token = try? tokens.token(forCard: serverCardID)
            else { continue }
            let status: String
            do {
                status = try await APIClient(baseURL: backend, transport: transport).cardStatus(cardID: serverCardID, token: token)
            } catch let problem as ProblemDetails where problem.type == "CARD-NOT-FOUND" {
                // Server tidak mengenali token ini (mis. hash belum terpasang): hapus lokal agar
                // perpanjangan bertanda tangan berikutnya memasang token baru (review akhir I1).
                try? tokens.delete(forCard: serverCardID)
                continue
            } catch {
                continue  // offline atau galat lain: status terakhir tetap dipakai (FR-25)
            }
            // Pembaruan terarah di dalam store: perubahan lain selama permintaan (mis. perpanjangan) tidak
            // tertimpa salinan kartu yang basi (review M4).
            let updated = try? await cards.update(id: card.id) { current in
                guard let next = Self.localStatus(server: status, current: current.status) else { return false }
                current.status = next
                return true
            }
            if updated == true { changed = true }
        }
        return changed
    }

    /// Status lokal baru, atau nil bila tidak berubah. Dicabut bersifat final dan menang atas apa pun.
    /// Kunci lokal yang hilang ("Perlu dipindahkan") tidak ditimpa penangguhan maupun pemulihan, dan
    /// ACTIVE hanya memulihkan kartu yang ditangguhkan.
    nonisolated static func localStatus(server: String, current: CardStatus) -> CardStatus? {
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

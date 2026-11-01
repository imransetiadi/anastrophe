import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import Foundation

/// Hapus kartu (FR-31, ADR-0026/0027/0028): cabut di server dengan bukti kepemilikan kunci, lalu
/// hapus kunci, record, dan kartu lokal. Bila server tidak terjangkau atau menolak, tidak ada
/// yang dihapus.
struct CardRemover: Sendable {
    let keys: any CredentialKeyStore
    let records: any CredentialRecordStore
    let cards: any CardStore
    /// Token baca status kartu ikut dihapus (ADR-0037).
    let statusTokens: (any StatusTokenStore)?
    let transport: any HTTPTransport

    init(keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore, statusTokens: (any StatusTokenStore)? = nil, transport: any HTTPTransport = URLSession.shared) {
        self.keys = keys
        self.records = records
        self.cards = cards
        self.statusTokens = statusTokens
        self.transport = transport
    }

    /// Jawaban server yang berarti kartu sudah tiada di sana (ADR-0027): boleh hapus lokal.
    static let alreadyGone: Set<String> = ["CARD-GONE", "CRED-NOT-FOUND"]

    /// Kredensial yang bisa membuktikan kepemilikan: punya backend penerbit dan kuncinya ada.
    func provableCredentials(of card: Card) throws -> [(Data, CredentialRecord)] {
        try card.credentials.values.sorted { $0.lexicographicallyPrecedes($1) }.compactMap { id in
            guard let record = try records.record(for: id), record.renewalURL != nil, try keys.hasKey(for: id) else { return nil }
            return (id, record)
        }
    }

    /// `context` boleh nil hanya bila tidak ada kredensial yang bisa membuktikan (ADR-0028).
    func remove(card: Card, context: AuthorizedContext?) async throws {
        let candidates = try provableCredentials(of: card)
        if !candidates.isEmpty {
            guard let context else { throw ANError.keyUnavailable }
            var lastError: (any Error)?
            var revoked = false
            for (credentialID, record) in candidates where !revoked {
                do {
                    try await revoke(credentialID: credentialID, record: record, context: context)
                    revoked = true
                } catch let problem as ProblemDetails where Self.alreadyGone.contains(problem.type) {
                    revoked = true
                } catch let problem as ProblemDetails {
                    lastError = problem  // coba kredensial kartu yang lain
                }
            }
            guard revoked else { throw lastError ?? ANError.internalError }
        }
        let serverCardIDs = Set(card.credentials.values.compactMap { try? records.record(for: $0)?.serverCardID })
        for credentialID in card.credentials.values {
            try? keys.deleteKey(for: credentialID)
            try? records.delete(credentialID)
        }
        for id in serverCardIDs { try? statusTokens?.delete(forCard: id) }
        do {
            try await cards.remove(id: card.id)
        } catch ANError.invalidData {
            // Kartu sudah terhapus (mis. ketuk ganda): hasil akhirnya sama.
        }
    }

    private func revoke(credentialID: Data, record: CredentialRecord, context: AuthorizedContext) async throws {
        guard let backend = record.renewalURL else { return }
        let api = APIClient(baseURL: backend, transport: transport)
        let challenge = try await api.renewalChallenge(credentialID: credentialID)
        guard let cardID = challenge.cardInstanceID ?? record.serverCardID else { throw ANError.invalidData }
        let signature = try keys.signer(for: credentialID, context: context).sign(challenge.revokeMessage(credentialID: credentialID, cardID: cardID))
        try await api.deleteCard(cardID: cardID, credentialID: credentialID, nonce: challenge.nonce, signature: signature, idempotencyKey: UUID())
    }
}

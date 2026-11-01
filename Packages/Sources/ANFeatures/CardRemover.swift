import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import Foundation

/// Hapus kartu (FR-31, ADR-0026): cabut di server dengan bukti kepemilikan kunci, lalu hapus
/// kunci, record, dan kartu lokal. Bila server tidak terjangkau, tidak ada yang dihapus.
struct CardRemover: Sendable {
    let keys: any CredentialKeyStore
    let records: any CredentialRecordStore
    let cards: any CardStore
    let transport: any HTTPTransport

    init(keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore, transport: any HTTPTransport = URLSession.shared) {
        self.keys = keys
        self.records = records
        self.cards = cards
        self.transport = transport
    }

    /// Jawaban server yang berarti kartu sudah tidak aktif di sana: lanjut hapus lokal.
    static let alreadyGone: Set<String> = ["CARD-NOT-FOUND", "CARD-NOT-REMOVABLE", "CRED-NOT-RENEWABLE", "CRED-NOT-FOUND"]

    func remove(card: Card, context: AuthorizedContext) async throws {
        let issued = card.credentials.values.lazy.compactMap { id -> (Data, CredentialRecord)? in
            guard let record = try? records.record(for: id), record.renewalURL != nil, record.serverCardID != nil else { return nil }
            return (id, record)
        }.first
        if let (credentialID, record) = issued, let backend = record.renewalURL, let cardID = record.serverCardID {
            let api = APIClient(baseURL: backend, transport: transport)
            do {
                let challenge = try await api.renewalChallenge(credentialID: credentialID)
                let signature = try keys.signer(for: credentialID, context: context).sign(challenge.revokeMessage(credentialID: credentialID, cardID: cardID))
                try await api.deleteCard(cardID: cardID, credentialID: credentialID, nonce: challenge.nonce, signature: signature, idempotencyKey: UUID())
            } catch let problem as ProblemDetails where Self.alreadyGone.contains(problem.type) {
                // Sudah dicabut atau tidak dikenal di server.
            }
        }
        for credentialID in card.credentials.values {
            try? keys.deleteKey(for: credentialID)
            try? records.delete(credentialID)
        }
        try await cards.remove(id: card.id)
    }
}

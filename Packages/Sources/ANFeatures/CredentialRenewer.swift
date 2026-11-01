import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import Foundation

/// Memperpanjang sertifikat kredensial dengan bukti kepemilikan kunci (FR-45, SDD §8.4.2).
/// Hanya dipanggil dengan konteks dari autentikasi tap (ADR-0023), sehingga tanda tangan
/// tidak memunculkan prompt kedua dan tidak pernah terjadi di background.
struct CredentialRenewer: Sendable {
    let keys: any CredentialKeyStore
    let records: any CredentialRecordStore
    let cards: any CardStore
    /// Token baca status (ADR-0037); kartu tanpa token mendapatkannya lewat perpanjangan ini.
    let statusTokens: (any StatusTokenStore)?
    let transport: any HTTPTransport

    init(keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore, statusTokens: (any StatusTokenStore)? = nil, transport: any HTTPTransport = URLSession.shared) {
        self.keys = keys
        self.records = records
        self.cards = cards
        self.statusTokens = statusTokens
        self.transport = transport
    }

    /// Mengembalikan kartu yang sudah diperbarui. Bila gagal di langkah mana pun, record lama
    /// tetap utuh.
    /// `shouldSign` dicek tepat sebelum tanda tangan: tidak ada tanda tangan dari background atau
    /// setelah perpanjangan dibatalkan.
    func renew(card: Card, channel: ChannelKind, context: AuthorizedContext, shouldSign: @Sendable () -> Bool = { true }) async throws -> Card {
        guard let credentialID = card.credentials[channel],
              let record = try records.record(for: credentialID),
              let backend = record.renewalURL
        else { throw ANError.keyUnavailable }
        let api = APIClient(baseURL: backend, transport: transport)
        let challenge = try await api.renewalChallenge(credentialID: credentialID)
        guard shouldSign() else { throw CancellationError() }
        let signature = try keys.signer(for: credentialID, context: context).sign(challenge.message(credentialID: credentialID))
        let serverCardID = record.serverCardID ?? challenge.cardInstanceID
        var newToken: Data?
        if let statusTokens, let serverCardID, (try? statusTokens.token(forCard: serverCardID)) == nil {
            newToken = try StatusToken.generate()
        }
        let renewed = try await api.renewCredential(credentialID: credentialID, nonce: challenge.nonce, signature: signature,
                                                    statusTokenHash: newToken.map(StatusToken.hash), idempotencyKey: UUID())
        guard renewed.credentialID == credentialID, renewed.channel == channel else { throw ANError.invalidData }
        let updated = record.renewed(certificate: renewed.certificate, notAfter: renewed.notAfter, notBefore: renewed.notBefore, groupKeys: renewed.groupKeys)
        _ = try updated.material(suspended: false)  // kunci reader group harus valid sebelum menimpa
        // Baca ulang kartu: perubahan selama perpanjangan (mis. status) tidak boleh tertimpa salinan
        // lama, dan kartu yang sudah dihapus tidak mendapat record baru.
        guard var current = try await cards.all().first(where: { $0.id == card.id }) else { throw ANError.keyUnavailable }
        try records.save(updated)
        current.notAfter = renewed.notAfter
        current.zones = renewed.zones
        try await cards.update(current)
        if let newToken, let serverCardID { try? statusTokens?.save(newToken, forCard: serverCardID) }
        return current
    }
}

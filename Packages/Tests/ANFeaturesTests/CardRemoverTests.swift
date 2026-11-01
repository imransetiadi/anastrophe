import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import CryptoKit
import Foundation
import LocalAuthentication
import Testing
@testable import ANFeatures

@Suite("Hapus kartu (FR-31, ADR-0026)")
struct CardRemoverTests {
    let secrets = InMemorySecretStore()
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
    let credentialID = Data(repeating: 0x5E, count: 16)
    let cardID = "6f1c2a9e-0000-4000-8000-000000000001"
    let context = AuthorizedContext(laContext: LAContext())
    var keys: DeviceKeyStore { DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory()) }
    var challengeReply: (status: Int, body: String, contentType: String) {
        (201, #"{"nonce":"\#(Data(repeating: 0x4E, count: 32).base64EncodedString())","expires_at":"2026-11-05T00:02:00Z"}"#, "application/json")
    }

    func setUp(backend: Bool) async throws -> (Card, SwiftDataCardStore, P256.Signing.PublicKey) {
        let publicKey = try P256.Signing.PublicKey(x963Representation: keys.createKey(for: credentialID))
        try records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: .now.addingTimeInterval(86_400), groupKeys: [:],
                                          renewalURL: backend ? URL(string: "http://127.0.0.1:8080") : nil, serverCardID: backend ? cardID : nil))
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: nil)
        try await cards.add(card)
        return (card, cards, publicKey)
    }

    func remover(_ cards: SwiftDataCardStore, _ transport: any HTTPTransport) -> CardRemover {
        CardRemover(keys: keys, records: records, cards: cards, transport: transport)
    }

    @Test func hapusMencabutLaluMenghapusLokal() async throws {
        let (card, cards, publicKey) = try await setUp(backend: true)
        let transport = SequenceTransport([challengeReply, (204, "", "application/json")])
        try await remover(cards, transport).remove(card: card, context: context)
        #expect(transport.paths == ["/v1/credentials/\(credentialID.hexString):challenge", "/v1/cards/\(cardID)"])
        let bodyData = try #require(transport.bodies[1])
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        let signatureBase64 = try #require(body["signature"])
        let signatureData = try #require(Data(base64Encoded: signatureBase64))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        let message = Data("ANP1-REVOKE".utf8) + credentialID + Data(repeating: 0x4E, count: 32) + Data(cardID.utf8)
        #expect(publicKey.isValidSignature(signature, for: message))
        #expect(secrets.storedKeyCount == 0)
        #expect(try records.record(for: credentialID) == nil)
        #expect(try await cards.all().isEmpty)
    }

    @Test func offlineKartuTetapAda() async throws {
        // Review Focus 3: server tak terjangkau → tidak ada yang dihapus.
        let (card, cards, _) = try await setUp(backend: true)
        await #expect(throws: (any Error).self) {
            try await remover(cards, SequenceTransport([challengeReply])).remove(card: card, context: context)
        }
        #expect(try keys.hasKey(for: credentialID))
        #expect(try records.record(for: credentialID) != nil)
        #expect(try await cards.all().count == 1)
    }

    @Test func sudahDicabutDiServerTetapDihapusLokal() async throws {
        let (card, cards, _) = try await setUp(backend: true)
        let transport = SequenceTransport([(409, #"{"type":"CRED-NOT-RENEWABLE","status":409}"#, "application/problem+json")])
        try await remover(cards, transport).remove(card: card, context: context)
        #expect(try await cards.all().isEmpty)
        #expect(secrets.storedKeyCount == 0)
    }

    @Test func tanpaBackendHapusLokalSaja() async throws {
        let (card, cards, _) = try await setUp(backend: false)
        let transport = SequenceTransport([])
        try await remover(cards, transport).remove(card: card, context: context)
        #expect(transport.paths.isEmpty)
        #expect(try await cards.all().isEmpty)
    }
}

/// Autentikasi yang selalu ditolak (pengguna membatalkan Face ID).
struct DenyingAuthenticator: UserAuthenticator {
    struct Cancelled: Error {}
    func authenticate(reason: String) async throws -> AuthorizedContext { throw Cancelled() }
}

@MainActor
@Suite("Hapus kartu lewat layanan app (FR-31: konfirmasi + autentikasi)")
struct RemoveCardServiceTests {
    func labCard(in services: AppServices) async throws -> Card {
        let credentialID = Data(repeating: 0x5E, count: 16)
        _ = try services.keys.createKey(for: credentialID)
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: nil)
        try await services.cards.add(card)
        return card
    }

    @Test func hapusKartuButuhAutentikasi() async throws {
        let denied = AppServices.inMemory(events: [.waitingForReader], authenticator: DenyingAuthenticator())
        let card = try await labCard(in: denied)
        await #expect(throws: (any Error).self) { try await denied.removeCard(card) }
        #expect(try await denied.cards.all().count == 1)

        let allowed = AppServices.inMemory()
        let other = try await labCard(in: allowed)
        try await allowed.removeCard(other)
        #expect(try await allowed.cards.all().isEmpty)
    }
}

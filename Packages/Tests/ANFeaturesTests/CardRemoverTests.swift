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

    func setUp(backend: Bool, storedCardID: Bool = true, withKey: Bool = true, addCard: Bool = true) async throws -> (Card, SwiftDataCardStore, P256.Signing.PublicKey?) {
        let publicKey = withKey ? try P256.Signing.PublicKey(x963Representation: keys.createKey(for: credentialID)) : nil
        try records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: .now.addingTimeInterval(86_400), groupKeys: [:],
                                          renewalURL: backend ? URL(string: "http://127.0.0.1:8080") : nil, serverCardID: backend && storedCardID ? cardID : nil))
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: nil)
        if addCard { try await cards.add(card) }
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
        #expect(try #require(publicKey).isValidSignature(signature, for: message))
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
        // ADR-0027: hanya CARD-GONE (atau CRED-NOT-FOUND) yang berarti kartu sudah tiada di server.
        let transport = SequenceTransport([(410, #"{"type":"CARD-GONE","status":410}"#, "application/problem+json")])
        try await remover(cards, transport).remove(card: card, context: context)
        #expect(try await cards.all().isEmpty)
        #expect(secrets.storedKeyCount == 0)
    }

    @Test func jawabanLainMempertahankanKartu() async throws {
        // Review hapus kartu I1: 409/500 tidak lagi dianggap "sudah tiada".
        let (card, cards, _) = try await setUp(backend: true)
        let transport = SequenceTransport([(409, #"{"type":"CRED-NOT-RENEWABLE","status":409}"#, "application/problem+json")])
        await #expect(throws: (any Error).self) { try await remover(cards, transport).remove(card: card, context: context) }
        #expect(try await cards.all().count == 1)
        #expect(try keys.hasKey(for: credentialID))
    }

    @Test func idKartuDariChallengeDipakai() async throws {
        // Review hapus kartu C1: record tanpa serverCardID (mis. kartu lama) tetap dicabut di server.
        let (card, cards, _) = try await setUp(backend: true, storedCardID: false)
        let challenge = #"{"nonce":"\#(Data(repeating: 0x4E, count: 32).base64EncodedString())","expires_at":"2026-11-05T00:02:00Z","card_instance_id":"\#(cardID)"}"#
        let transport = SequenceTransport([(201, challenge, "application/json"), (204, "", "application/json")])
        try await remover(cards, transport).remove(card: card, context: context)
        #expect(transport.paths.last == "/v1/cards/\(cardID)")
        #expect(try await cards.all().isEmpty)
    }

    @Test func tanpaKunciHapusLokalTanpaServer() async throws {
        // ADR-0028: bukti mustahil tanpa kunci → hapus lokal saja.
        let (card, cards, _) = try await setUp(backend: true, withKey: false)
        let transport = SequenceTransport([])
        try await remover(cards, transport).remove(card: card, context: nil)
        #expect(transport.paths.isEmpty)
        #expect(try records.record(for: credentialID) == nil)
        #expect(try await cards.all().isEmpty)
    }

    @Test func kartuSudahTerhapusLokalDianggapSukses() async throws {
        // Review hapus kartu I3: ketuk ganda tidak berakhir dengan pesan gagal.
        let (card, cards, _) = try await setUp(backend: false, addCard: false)
        try await remover(cards, SequenceTransport([])).remove(card: card, context: context)
        #expect(try records.record(for: credentialID) == nil)
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

    @Test func tanpaKunciTanpaPasscodeTetapBisaDihapus() async throws {
        // ADR-0028: kartu tanpa kunci tetap bisa dihapus walau passcode tidak disetel.
        let services = AppServices.inMemory(events: [.waitingForReader], authenticator: PasscodeNotSetAuthenticator())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: Data(repeating: 0x5F, count: 16)], notAfter: nil)
        try await services.cards.add(card)
        try await services.removeCard(card)
        #expect(try await services.cards.all().isEmpty)
    }

    @Test func denganKunciTanpaPasscodeDitolak() async throws {
        let services = AppServices.inMemory(events: [.waitingForReader], authenticator: PasscodeNotSetAuthenticator())
        let card = try await labCard(in: services)
        await #expect(throws: (any Error).self) { try await services.removeCard(card) }
        #expect(try await services.cards.all().count == 1)
    }

    @Test func hapusKartuMenghapusRiwayat() async throws {
        // Review Focus 2 (FR-30/FR-31): riwayat tap ikut terhapus bersama kartunya.
        let services = AppServices.inMemory()
        let card = try await labCard(in: services)
        let other = Card(id: UUID(), name: "Parkir", siteName: "Gedung Lab", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await services.cards.add(other)
        try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now, channel: .ble, granted: true, denyReason: nil))
        try await services.tapHistory.append(TapEntry(cardID: other.id, date: .now, channel: .ble, granted: true, denyReason: nil))
        try await services.removeCard(card)
        #expect(try await services.tapHistory.entries(for: card.id, since: .distantPast).isEmpty)
        #expect(try await services.tapHistory.entries(for: other.id, since: .distantPast).count == 1)  // kartu lain utuh
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

/// Perangkat tanpa passcode: LocalAuthentication tidak bisa mengautentikasi.
struct PasscodeNotSetAuthenticator: UserAuthenticator {
    func authenticate(reason: String) async throws -> AuthorizedContext { throw LAError(.passcodeNotSet) }
}

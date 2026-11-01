import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import CryptoKit
import Foundation
import LocalAuthentication
import Testing
@testable import ANFeatures

@Suite("Perpanjangan sertifikat di app (FR-45, ADR-0023)")
struct CredentialRenewerTests {
    let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
    let credentialID = Data(repeating: 0x5E, count: 16)
    let backend = URL(string: "http://127.0.0.1:8080")!
    let nonce = Data(repeating: 0x4E, count: 32)
    let context = AuthorizedContext(laContext: LAContext())

    /// Kartu aktif dengan record lama (sertifikat 0xAA, berlaku sampai 2026-11-08).
    func setUp(renewalURL: URL?) throws -> (Card, SwiftDataCardStore, P256.Signing.PublicKey, CredentialRecord) {
        let publicKey = try P256.Signing.PublicKey(x963Representation: keys.createKey(for: credentialID))
        let record = CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: Date(timeIntervalSince1970: 1_794_096_000),
                                      groupKeys: ["a1a2a3a4a5a6a7a8": [P256.Signing.PrivateKey().publicKey.x963Representation]], notBefore: Date(timeIntervalSince1970: 1_793_491_200), renewalURL: renewalURL)
        try records.save(record)
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: ["Pintu Lab"], status: .active, credentials: [.ble: credentialID], notAfter: record.notAfter)
        return (card, cards, publicKey, record)
    }

    var challengeReply: (status: Int, body: String, contentType: String) {
        (201, #"{"nonce":"\#(nonce.base64EncodedString())","expires_at":"2026-11-05T00:02:00Z"}"#, "application/json")
    }

    @Test func perpanjanganMemperbaruiRecordDanKartu() async throws {
        let (card, cards, publicKey, _) = try setUp(renewalURL: backend)
        try await cards.add(card)
        let transport = SequenceTransport([
            challengeReply,
            (200, provisionedBody(credentialID: credentialID, notAfter: "2026-11-12T00:00:00Z", notBefore: "2026-11-05T00:00:00Z"), "application/json"),
        ])
        let renewed = try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        let newNotAfter = Date(timeIntervalSince1970: 1_794_441_600)
        #expect(renewed.notAfter == newNotAfter)
        #expect(try await cards.all().first?.notAfter == newNotAfter)
        let record = try #require(try records.record(for: credentialID))
        #expect(record.certificate == Data(repeating: 0xCE, count: 188))
        #expect(record.notBefore == Date(timeIntervalSince1970: 1_793_836_800))
        #expect(record.renewalURL == backend)
        // Bukti kepemilikan: tanda tangan kunci kredensial atas "ANP1-RENEW" ‖ cred_id ‖ nonce.
        #expect(transport.paths == ["/v1/credentials/\(credentialID.hexString):challenge", "/v1/credentials/\(credentialID.hexString):renew"])
        let bodyData = try #require(transport.bodies[1])
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        let signatureBase64 = try #require(body["signature"])
        let signatureData = try #require(Data(base64Encoded: signatureBase64))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        #expect(publicKey.isValidSignature(signature, for: Data("ANP1-RENEW".utf8) + credentialID + nonce))
        #expect(body["nonce"] == nonce.base64EncodedString())
    }

    @Test func gagalJaringanRecordUtuh() async throws {
        let (card, cards, _, record) = try setUp(renewalURL: backend)
        try await cards.add(card)
        let transport = SequenceTransport([challengeReply])  // renew → URLError
        await #expect(throws: (any Error).self) {
            try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        }
        #expect(try records.record(for: credentialID) == record)
        #expect(try await cards.all() == [card])
    }

    @Test func responsCredIDBerbedaDitolak() async throws {
        // Review Focus 3: respons untuk kredensial lain tidak boleh menimpa record ini.
        let (card, cards, _, record) = try setUp(renewalURL: backend)
        try await cards.add(card)
        let transport = SequenceTransport([
            challengeReply,
            (200, provisionedBody(credentialID: Data(repeating: 0x77, count: 16), notAfter: "2026-11-12T00:00:00Z"), "application/json"),
        ])
        await #expect(throws: ANError.invalidData) {
            try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        }
        #expect(try records.record(for: credentialID) == record)
    }

    @Test func tanpaRenewalURLTidakMenghubungiServer() async throws {
        // Kartu lab_ca.py tidak punya backend penerbit.
        let (card, cards, _, _) = try setUp(renewalURL: nil)
        let transport = SequenceTransport([])
        await #expect(throws: ANError.keyUnavailable) {
            try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        }
        #expect(transport.paths.isEmpty)
    }

    @Test func responsKanalBerbedaDitolak() async throws {
        // Review perpanjangan M1: separuh Review Focus 3 (kanal) kini diuji.
        let (card, cards, _, record) = try setUp(renewalURL: backend)
        try await cards.add(card)
        let transport = SequenceTransport([
            challengeReply,
            (200, provisionedBody(credentialID: credentialID, notAfter: "2026-11-12T00:00:00Z", channel: "nfcHCE"), "application/json"),
        ])
        await #expect(throws: ANError.invalidData) {
            try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        }
        #expect(try records.record(for: credentialID) == record)
    }

    @Test func kunciGroupTidakValidDitolak() async throws {
        let (card, cards, _, record) = try setUp(renewalURL: backend)
        try await cards.add(card)
        let invalidPoint = Data([0x04] + [UInt8](repeating: 0x04, count: 64)).base64EncodedString()
        let transport = SequenceTransport([
            challengeReply,
            (200, provisionedBody(credentialID: credentialID, groupKey: invalidPoint, notAfter: "2026-11-12T00:00:00Z"), "application/json"),
        ])
        await #expect(throws: (any Error).self) {
            try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        }
        #expect(try records.record(for: credentialID) == record)
    }

    @Test func statusKartuTidakTertimpaSaatPerpanjangan() async throws {
        // Review perpanjangan M4: perubahan status selama perpanjangan tidak boleh hilang.
        let (card, cards, _, _) = try setUp(renewalURL: backend)
        try await cards.add(card)
        var changed = card
        changed.status = .suspended
        let suspended = changed
        let transport = HookTransport(replies: [
            challengeReply,
            (200, provisionedBody(credentialID: credentialID, notAfter: "2026-11-12T00:00:00Z"), "application/json"),
        ]) { try? await cards.update(suspended) }
        _ = try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        let stored = try #require(try await cards.all().first)
        #expect(stored.status == .suspended)
        #expect(stored.notAfter == Date(timeIntervalSince1970: 1_794_441_600))
    }

    @Test func perpanjanganMempertahankanIDKartuServer() async throws {
        // Review hapus kartu C1: perpanjangan tidak boleh menghapus serverCardID.
        _ = try keys.createKey(for: credentialID)
        try records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: Date(timeIntervalSince1970: 1_794_096_000),
                                          groupKeys: ["a1a2a3a4a5a6a7a8": [P256.Signing.PrivateKey().publicKey.x963Representation]], renewalURL: backend, serverCardID: "card-1"))
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: nil)
        try await cards.add(card)
        let transport = SequenceTransport([challengeReply, (200, provisionedBody(credentialID: credentialID, notAfter: "2026-11-12T00:00:00Z"), "application/json")])
        _ = try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport).renew(card: card, channel: .ble, context: context)
        #expect(try records.record(for: credentialID)?.serverCardID == "card-1")
    }
}

/// Menjawab berurutan; menjalankan `onFirst` saat permintaan pertama (meniru perubahan bersamaan).
final class HookTransport: HTTPTransport, @unchecked Sendable {
    private let replies: LockedReplies
    private let onFirst: @Sendable () async -> Void

    init(replies: [(status: Int, body: String, contentType: String)], onFirst: @escaping @Sendable () async -> Void) {
        self.replies = LockedReplies(replies)
        self.onFirst = onFirst
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (reply, first) = replies.next()
        if first { await onFirst() }
        guard let reply else { throw URLError(.cannotConnectToHost) }
        return (Data(reply.body.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": reply.contentType])!)
    }
}

final class LockedReplies: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(status: Int, body: String, contentType: String)]
    private var served = 0

    init(_ replies: [(status: Int, body: String, contentType: String)]) { self.replies = replies }

    func next() -> ((status: Int, body: String, contentType: String)?, Bool) {
        lock.withLock {
            defer { served += 1 }
            return (replies.isEmpty ? nil : replies.removeFirst(), served == 0)
        }
    }
}

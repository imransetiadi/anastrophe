import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import CryptoKit
import Foundation
import Testing
@testable import ANFeatures

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "anastrophe-tests-\(UUID().uuidString)")
}

/// JSON seperti keluaran `scripts/anp1/lab_ca.py issue`.
func labJSON(credentialID: Data, channel: ChannelKind = .ble) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(ProvisionedCredential(
        credentialID: credentialID,
        channel: channel,
        certificate: Data(repeating: 0xCE, count: 188),
        notAfter: Date(timeIntervalSince1970: 1_794_096_000),
        siteName: "Gedung Lab",
        zones: ["Pintu Lab"],
        groupKeys: ["a1a2a3a4a5a6a7a8": [P256.Signing.PrivateKey().publicKey.x963Representation]]
    ))
}

/// Identitas kartu lab untuk enrolment lewat registri (ADR-0031).
let labTestCard = CardIdentity("iso14443a:04a1b2c3d4e5f6")!

/// Transport palsu yang menjawab berurutan, mencatat permintaan.
final class SequenceTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, String, String)]
    private(set) var paths: [String] = []
    private(set) var bodies: [Data?] = []
    private(set) var authorizations: [String?] = []

    init(_ replies: [(status: Int, body: String, contentType: String)]) {
        self.replies = replies.map { ($0.status, $0.body, $0.contentType) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: (Int, String, String)? = lock.withLock {
            paths.append(request.url?.path(percentEncoded: false) ?? "")
            bodies.append(request.httpBody)
            authorizations.append(request.value(forHTTPHeaderField: "Authorization"))
            return replies.isEmpty ? nil : replies.removeFirst()
        }
        guard let (status, body, contentType) = reply else { throw URLError(.cannotConnectToHost) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!)
    }
}

/// `GET /v1/config` backend dev (kill switch kanal).
func configBody(_ channels: [String] = ["ble"]) -> (status: Int, body: String, contentType: String) {
    (200, #"{"enabled_channels":[\#(channels.map { "\"\($0)\"" }.joined(separator: ",")) ],"wallet_program_enabled":false}"#, "application/json")
}

func provisionedBody(credentialID: Data, groupKey: String? = nil, notAfter: String = "2026-11-08T00:00:00Z", notBefore: String? = nil, channel: String = "ble") -> String {
    let groupKey = groupKey ?? P256.Signing.PrivateKey().publicKey.x963Representation.base64EncodedString()
    return #"{"credential_id":"\#(credentialID.base64EncodedString())","channel":"\#(channel)","certificate":"\#(Data(repeating: 0xCE, count: 188).base64EncodedString())",\#(notBefore.map { #""not_before":"\#($0)","# } ?? "")"not_after":"\#(notAfter)","site_name":"Gedung Lab","zones":["Pintu Lab"],"group_keys":{"a1a2a3a4a5a6a7a8":["\#(groupKey)"]}}"#
}

@Suite("Provisioning lab lewat backend dev (rencana lab end-to-end)")
struct LabBackendProvisioningTests {
    let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
    let base = URL(string: "http://127.0.0.1:8080")!

    @Test func provisionViaBackendMembuatKartuAktif() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let serverCredID = Data(repeating: 0x5E, count: 16)
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"6f1c2a9e-0000-4000-8000-000000000001","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: serverCredID), "application/json"),
        ])
        let card = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble, keys: keys, records: records, cards: cards)
        #expect(card.status == .active)
        #expect(card.credentials[.ble] == serverCredID)
        #expect(try keys.hasKey(for: serverCredID))
        #expect(try records.record(for: serverCredID) != nil)
        #expect(transport.paths == ["/v1/config", "/v1/enrollments", "/v1/enrollments/6f1c2a9e-0000-4000-8000-000000000001/credentials"])
    }

    @Test func provisionViaBackendBerhentiSaatMenungguPersetujuan() async throws {
        // ADR-0032: perangkat tambahan menunggu operator; tanpa provisioning dan tanpa kunci,
        // record, atau kartu yang tersisa (FR-19).
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(), (201, #"{"enrollment_id":"e1","status":"PENDING_APPROVAL"}"#, "application/json")])
        await #expect(throws: ANError.enrollmentRejected(.pendingApproval)) {
            try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: self.base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble, keys: keys, records: self.records, cards: cards)
        }
        #expect(transport.paths == ["/v1/config", "/v1/enrollments"])
        #expect(secrets.storedKeyCount == 0)
        #expect(try await cards.all().isEmpty)
    }

    @Test func provisionViaBackendDenganUndangan() async throws {
        // ADR-0033: body enrolment membawa token undangan, bukan identitas kartu.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let token = String(repeating: "A", count: 42) + "w"
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5D, count: 16)), "application/json"),
        ])
        let card = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, invitation: token, channel: .ble, keys: keys, records: records, cards: cards)
        #expect(card.status == .active)
        let enrolment = try #require(transport.bodies[1])
        let body = try #require(try JSONSerialization.jsonObject(with: enrolment) as? [String: String])
        #expect(body["device_id"] == "dev" && body["invitation"] == token && body["provisioning_key_hash"] != nil)
        #expect(body.keys.sorted() == ["device_id", "invitation", "provisioning_key_hash"])
    }

    @Test func provisionViaBackendMenyimpanTokenStatus() async throws {
        // ADR-0037: token disimpan di bawah id card instance server; server hanya menerima hash-nya.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let tokens = KeychainStatusTokenStore(store: InMemorySecretStore())
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5D, count: 16)), "application/json"),
        ])
        _ = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble,
                                                          keys: keys, records: records, cards: cards, statusTokens: tokens)
        let token = try #require(try tokens.token(forCard: "e1"))
        let raw = try #require(transport.bodies[2])
        let body = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: String])
        #expect(body["status_token_hash"] == StatusToken.hash(token).base64EncodedString())
    }

    @Test func provisionViaBackendMemakaiTokenYangAda() async throws {
        // Review akhir I1: server hanya memasang hash bila belum ada, jadi app memakai ulang tokennya.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let tokens = KeychainStatusTokenStore(store: InMemorySecretStore())
        let existing = Data(repeating: 0x44, count: 32)
        try tokens.save(existing, forCard: "e1")
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5D, count: 16)), "application/json"),
        ])
        _ = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble,
                                                          keys: keys, records: records, cards: cards, statusTokens: tokens)
        let raw = try #require(transport.bodies[2])
        let body = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: String])
        #expect(body["status_token_hash"] == StatusToken.hash(existing).base64EncodedString())
        #expect(try tokens.token(forCard: "e1") == existing)
    }

    @Test func provisionViaBackendMemakaiRahasiaEnrolment() async throws {
        // ADR-0040: rahasia yang hash-nya dikirim saat enrolment dibawa sebagai bearer saat provisioning.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5D, count: 16)), "application/json"),
        ])
        _ = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble,
                                                          keys: keys, records: records, cards: cards)
        let raw = try #require(transport.bodies[1])
        let body = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let hash = try #require(body["provisioning_key_hash"] as? String)
        let bearer = try #require(transport.authorizations[2])
        let encoded = String(try #require(bearer.split(separator: " ").last))
        var padded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        let secret = try #require(Data(base64Encoded: padded))
        #expect(bearer.hasPrefix("Bearer ") && secret.count == 32)
        #expect(ProvisioningSecretGenerator.hash(ProvisioningSecret(raw: secret)).raw.base64EncodedString() == hash)
        #expect(transport.authorizations[1] == nil)  // enrolment tidak membawa rahasia mentah
    }

    @Test func provisionViaBackendMenyimpanRenewalURL() async throws {
        // ADR-0023: record mengingat backend penerbit dan awal masa berlaku untuk perpanjangan.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let serverCredID = Data(repeating: 0x5F, count: 16)
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: serverCredID, notBefore: "2026-11-01T00:00:00Z"), "application/json"),
        ])
        _ = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble, keys: keys, records: records, cards: cards)
        let record = try #require(try records.record(for: serverCredID))
        #expect(record.renewalURL == base)
        #expect(record.notBefore == Date(timeIntervalSince1970: 1_793_491_200))
        #expect(record.serverCardID == "e1")  // ADR-0026: ID kartu server untuk hapus kartu
    }

    @Test(arguments: [
        [configBody(), (409, #"{"type":"ENR-LIMIT","status":409}"#, "application/problem+json")],
        [configBody(), (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"), (400, #"{"type":"ENR-INVALID-KEY","status":400}"#, "application/problem+json")],
        // Review lab M2: jaringan putus setelah enrolment (transport habis → URLError).
        [configBody(), (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json")],
        // Review lab M2: gagal setelah kunci dipindah (kunci reader group tidak valid).
        [configBody(), (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
         (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16), groupKey: Data([0x04] + [UInt8](repeating: 0x04, count: 64)).base64EncodedString()), "application/json")],
    ])
    func provisionViaBackendGagalTidakMenyisakanKunci(replies: [(Int, String, String)]) async throws {
        // Review Focus 1: FR-19 — tidak ada kunci, record, atau kartu yatim.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport(replies.map { (status: $0.0, body: $0.1, contentType: $0.2) })
        await #expect(throws: (any Error).self) {
            try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble, keys: keys, records: records, cards: cards)
        }
        #expect(secrets.storedKeyCount == 0)
        #expect(try await cards.all().isEmpty)
    }

    @Test func provisionViaBackendKanalResponsBerbedaDitolak() async throws {
        // Review lab M7: server menjawab kanal lain → tidak ada kartu atau kunci tersisa.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([
            configBody(["ble", "nfcHCE"]),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16), channel: "nfcHCE"), "application/json"),
        ])
        await #expect(throws: ANError.invalidData) {
            try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble, keys: keys, records: records, cards: cards)
        }
        #expect(secrets.storedKeyCount == 0)
        #expect(try await cards.all().isEmpty)
    }

    @Test func provisionViaBackendKanalTidakAktifTidakMendaftar() async throws {
        // Review lab I1: kanal yang dimatikan backend ditolak sebelum enrolment, jadi slot
        // kartu server tidak terpakai.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble"])])
        await #expect(throws: ANError.channelUnavailable(.regionBlocked)) {
            try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .nfcHCE, keys: keys, records: records, cards: cards)
        }
        #expect(transport.paths == ["/v1/config"])
        #expect(secrets.storedKeyCount == 0)
    }

    @Test func provisionViaBackendDitolakLokalSaatDelapanKartu() async throws {
        // Batas 8 kartu juga di app (CLAUDE.md aturan 8): jangan buat enrolment server yang
        // kartunya pasti ditolak penyimpanan lokal.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        for i in 0..<8 {
            try await cards.add(Card(id: UUID(), name: "Kartu \(i)", siteName: "A", zones: [], status: .active, credentials: [:], notAfter: nil))
        }
        let transport = SequenceTransport([])
        await #expect(throws: ANError.cardLimitReached) {
            try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", card: labTestCard, channel: .ble, keys: keys, records: records, cards: cards)
        }
        #expect(transport.paths.isEmpty)
        #expect(secrets.storedKeyCount == 0)
    }
}

@Suite("Provisioning lab (DEBUG, rencana R1 Task 9)")
struct LabProvisioningTests {
    let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())

    @Test func beginMembuatKunciUntukCredentialBaru() throws {
        let (credentialID, publicKey) = try LabProvisioning.begin(keys: keys)
        #expect(credentialID.count == 16)
        #expect(publicKey.count == 65)
        #expect(try keys.hasKey(for: credentialID))
    }

    @Test func imporJSONLabMenghasilkanKartuAktif() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let (credentialID, _) = try LabProvisioning.begin(keys: keys)
        let card = try await LabProvisioning.complete(json: labJSON(credentialID: credentialID), keys: keys, records: records, cards: cards)
        #expect(card.status == .active)
        #expect(card.credentials[.ble] == credentialID)
        #expect(card.siteName == "Gedung Lab")
        #expect(try await cards.all() == [card])
        let material = try #require(try records.record(for: credentialID)).material(suspended: false)
        #expect(material.groupKeys.count == 1)
    }

    @Test func imporDitolakBilaSudahDelapanKartu() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        for i in 0..<8 {
            try await cards.add(Card(id: UUID(), name: "Kartu \(i)", siteName: "A", zones: [], status: .active, credentials: [:], notAfter: nil))
        }
        let (credentialID, _) = try LabProvisioning.begin(keys: keys)
        await #expect(throws: ANError.cardLimitReached) {
            try await LabProvisioning.complete(json: try labJSON(credentialID: credentialID), keys: keys, records: records, cards: cards)
        }
        // FR-19: tidak ada kredensial yatim.
        #expect(try records.record(for: credentialID) == nil)
        #expect(try !keys.hasKey(for: credentialID))
    }

    @Test func credentialIDTidakCocokDitolak() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let (credentialID, _) = try LabProvisioning.begin(keys: keys)
        await #expect(throws: ANError.invalidData) {
            try await LabProvisioning.complete(json: try labJSON(credentialID: Data(repeating: 0x99, count: 16)), keys: keys, records: records, cards: cards)
        }
        #expect(try await cards.all().isEmpty)
        #expect(try keys.hasKey(for: credentialID))  // kunci yang benar tetap ada untuk dicoba lagi
    }
}

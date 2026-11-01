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

/// Transport palsu yang menjawab berurutan, mencatat permintaan.
final class SequenceTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, String, String)]
    private(set) var paths: [String] = []

    init(_ replies: [(status: Int, body: String, contentType: String)]) {
        self.replies = replies.map { ($0.status, $0.body, $0.contentType) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body, contentType) = lock.withLock {
            paths.append(request.url?.path() ?? "")
            return replies.removeFirst()
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!)
    }
}

func provisionedBody(credentialID: Data) -> String {
    let groupKey = P256.Signing.PrivateKey().publicKey.x963Representation.base64EncodedString()
    return #"{"credential_id":"\#(credentialID.base64EncodedString())","channel":"ble","certificate":"\#(Data(repeating: 0xCE, count: 188).base64EncodedString())","not_after":"2026-11-08T00:00:00Z","site_name":"Gedung Lab","zones":["Pintu Lab"],"group_keys":{"a1a2a3a4a5a6a7a8":["\#(groupKey)"]}}"#
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
            (201, #"{"enrollment_id":"6f1c2a9e-0000-4000-8000-000000000001"}"#, "application/json"),
            (200, provisionedBody(credentialID: serverCredID), "application/json"),
        ])
        let card = try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", channel: .ble, keys: keys, records: records, cards: cards)
        #expect(card.status == .active)
        #expect(card.credentials[.ble] == serverCredID)
        #expect(try keys.hasKey(for: serverCredID))
        #expect(try records.record(for: serverCredID) != nil)
        #expect(transport.paths == ["/v1/enrollments", "/v1/enrollments/6f1c2a9e-0000-4000-8000-000000000001/credentials"])
    }

    @Test(arguments: [
        [(409, #"{"type":"ENR-LIMIT","status":409}"#, "application/problem+json")],
        [(201, #"{"enrollment_id":"e1"}"#, "application/json"), (400, #"{"type":"ENR-INVALID-KEY","status":400}"#, "application/problem+json")],
    ])
    func provisionViaBackendGagalTidakMenyisakanKunci(replies: [(Int, String, String)]) async throws {
        // Review Focus 1: FR-19 — tidak ada kunci, record, atau kartu yatim.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport(replies.map { (status: $0.0, body: $0.1, contentType: $0.2) })
        await #expect(throws: (any Error).self) {
            try await LabProvisioning.provisionViaBackend(api: APIClient(baseURL: base, transport: transport), deviceID: "dev", siteID: "site", channel: .ble, keys: keys, records: records, cards: cards)
        }
        #expect(secrets.storedKeyCount == 0)
        #expect(try await cards.all().isEmpty)
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

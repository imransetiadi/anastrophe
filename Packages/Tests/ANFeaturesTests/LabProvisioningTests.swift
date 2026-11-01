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

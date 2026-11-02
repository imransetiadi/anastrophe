import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@Suite("Provisioning produksi dan pemilihan kanal (FR-05, ADR-0043)")
struct CardProvisionerTests {
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
    let base = URL(string: "http://127.0.0.1:8080")!
    let enrolled = (201, #"{"enrollment_id":"6f1c2a9e-0000-4000-8000-000000000001","status":"PROVISIONING"}"#, "application/json")

    func provisioner(_ transport: SequenceTransport, secrets: InMemorySecretStore = InMemorySecretStore(), cards: any CardStore) -> CardProvisioner {
        CardProvisioner(api: APIClient(baseURL: base, transport: transport), keys: DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory()),
                        records: records, cards: cards, statusTokens: nil)
    }

    func json(_ data: Data?) throws -> [String: Any] {
        let body = try #require(data)
        let object = try JSONSerialization.jsonObject(with: body)
        return try #require(object as? [String: Any])
    }

    @Test func kanalOtomatisMemilihHCEDulu() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"]), enrolled,
                                           (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16), channel: "nfcHCE"), "application/json")])
        let outcome = try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                               channel: .automatic([.nfcHCE: .available, .ble: .available]))
        guard case .added(let card) = outcome else { Issue.record("hasil \(outcome)"); return }
        #expect(card.credentials[.nfcHCE] != nil)
        #expect(try json(transport.bodies[2])["channel"] as? String == "nfcHCE")
    }

    @Test func kanalOtomatisJatuhKeBLE() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"]), enrolled,
                                           (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16)), "application/json")])
        _ = try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                     channel: .automatic([.nfcHCE: .notEligible, .ble: .available]))
        #expect(try json(transport.bodies[2])["channel"] as? String == "ble")
    }

    @Test func bluetoothMatiTetapBisaDiprovisikan() async throws {
        // Provisioning tidak butuh radio; presentasi yang memberi panduan (FR-82).
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble"]), enrolled,
                                           (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16)), "application/json")])
        _ = try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                     channel: .automatic([.ble: .bluetoothOff]))
        #expect(try json(transport.bodies[2])["channel"] as? String == "ble")
    }

    @Test func tanpaKanalTidakMendaftar() async throws {
        // Anti-goal: enrolment tidak boleh memakan slot server bila tidak ada kanal yang bisa diprovisikan.
        let secrets = InMemorySecretStore()
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["nfcHCE"])])
        await #expect(throws: ANError.channelUnavailable(.notEligible)) {
            try await provisioner(transport, secrets: secrets, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                                       channel: .automatic([.nfcHCE: .unsupportedDevice, .ble: .available]))
        }
        #expect(transport.paths == ["/v1/config"])
        #expect(secrets.storedKeyCount == 0)
    }

    @Test func kanalDimatikanServerDitolakSebagaiWilayah() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody([])])
        await #expect(throws: ANError.channelUnavailable(.regionBlocked)) {
            try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                     channel: .automatic([.nfcHCE: .available, .ble: .available]))
        }
        #expect(transport.paths == ["/v1/config"])
    }

    @Test func menungguPersetujuanMenjadiHasil() async throws {
        let secrets = InMemorySecretStore()
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(), (201, #"{"enrollment_id":"e1","status":"PENDING_APPROVAL"}"#, "application/json")])
        let outcome = try await provisioner(transport, secrets: secrets, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                                                 channel: .automatic([.ble: .available]))
        #expect(outcome == .pendingApproval)
        #expect(secrets.storedKeyCount == 0)
        #expect(try await cards.all().isEmpty)
    }

    @Test func kanalGedungDiperiksaSebelumEnrolment() async throws {
        // ADR-0049, Review Focus 3: jalur kartu sudah tahu kanal gedung dari lookup, jadi tidak ada slot
        // server yang terbuang bila kanal gedung tidak bisa dipakai di iPhone ini.
        let secrets = InMemorySecretStore()
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"])])
        await #expect(throws: ANError.siteChannelUnavailable) {
            try await provisioner(transport, secrets: secrets, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                                       channel: .automatic([.nfcHCE: .unsupportedDevice, .ble: .available], siteChannels: [.nfcHCE]))
        }
        #expect(transport.paths == ["/v1/config"])
        #expect(secrets.storedKeyCount == 0)
    }

    @Test func kanalGedungKosongPesanNetral() async throws {
        // Review akhir (Minor 2, dinaikkan): kanal efektif gedung kosong → tidak ada iPhone yang bisa, jadi
        // pesannya tidak menyalahkan iPhone ini.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble"])])
        await #expect(throws: ANError.siteChannelsNotOffered) {
            try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                     channel: .automatic([.ble: .available], siteChannels: []))
        }
    }

    @Test func kanalGedungTerhalangBuildPesanNetral() async throws {
        // Build tanpa emulasi (entitlementMissing) bukan kesalahan iPhone pengguna.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"])])
        await #expect(throws: ANError.siteChannelsNotOffered) {
            try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                     channel: .automatic([.nfcHCE: .entitlementMissing, .ble: .available], siteChannels: [.nfcHCE]))
        }
    }

    @Test func kanalDipilihUlangSesudahEnrolment() async throws {
        // Jalur undangan baru tahu kanal gedung dari respons enrolment.
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"]),
                                           (201, #"{"enrollment_id":"e1","status":"PROVISIONING","channels":["ble"]}"#, "application/json"),
                                           (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16)), "application/json")])
        _ = try await provisioner(transport, cards: cards).provision(.invitation(token: String(repeating: "A", count: 42) + "w"), deviceID: "dev",
                                                                     channel: .automatic([.nfcHCE: .available, .ble: .available]))
        #expect(try json(transport.bodies[2])["channel"] as? String == "ble")
    }

    @Test func tanpaKanalGedungSesudahEnrolmentTanpaProvisioning() async throws {
        let secrets = InMemorySecretStore()
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"]),
                                           (201, #"{"enrollment_id":"e1","status":"PROVISIONING","channels":["nfcHCE"]}"#, "application/json")])
        await #expect(throws: ANError.siteChannelUnavailable) {
            try await provisioner(transport, secrets: secrets, cards: cards).provision(.invitation(token: String(repeating: "A", count: 42) + "w"), deviceID: "dev",
                                                                                       channel: .automatic([.nfcHCE: .unsupportedDevice, .ble: .available]))
        }
        #expect(transport.paths == ["/v1/config", "/v1/enrollments"])
        #expect(secrets.storedKeyCount == 0)
        #expect(try await cards.all().isEmpty)
    }

    @Test func serverLamaTanpaKanalGedung() async throws {
        // Review Focus 4: respons tanpa "channels" = semua kanal global (perilaku sebelum ADR-0049).
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let transport = SequenceTransport([configBody(["ble", "nfcHCE"]), enrolled,
                                           (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16), channel: "nfcHCE"), "application/json")])
        _ = try await provisioner(transport, cards: cards).provision(.card(siteID: "site", identity: labTestCard), deviceID: "dev",
                                                                     channel: .automatic([.nfcHCE: .available, .ble: .available]))
        #expect(try json(transport.bodies[2])["channel"] as? String == "nfcHCE")
    }

    @Test func undanganMembawaToken() async throws {
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let token = String(repeating: "A", count: 42) + "w"
        let transport = SequenceTransport([configBody(), enrolled,
                                           (200, provisionedBody(credentialID: Data(repeating: 0x5D, count: 16)), "application/json")])
        _ = try await provisioner(transport, cards: cards).provision(.invitation(token: token), deviceID: "dev", channel: .automatic([.ble: .available]))
        let body = try json(transport.bodies[1])
        #expect(body["invitation"] as? String == token)
        #expect(body["device_id"] as? String == "dev")
        #expect(body["site_id"] == nil && body["card"] == nil)
    }
}

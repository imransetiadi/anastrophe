import ANCore
import ANNetworking
import ANStorage
import CryptoKit
import Foundation
import Testing
@testable import ANFeatures

@Suite("Target backend lab (argumen peluncuran DEBUG)")
struct LabBackendTargetTests {
    @MainActor
    @Test func argumenLabAlurTambahKartu() {
        // E2e alur Tambah Kartu di simulator (ADR-0043): pembaca palsu, tautan undangan, kode gedung.
        let token = String(repeating: "A", count: 42) + "w"
        let services = AppServices.inMemory()
        services.configureLabBackend(arguments: ["Anastrophe", "-ANLabCardReader", "iso14443a:04a1b2c3d4e5f6",
                                                 "-ANLabOpenURL", "https://contoh.test/i/\(token)", "-ANLabAddCode", "7K2Q-9XA4"])
        #expect(services.labCardIdentity == CardIdentity("iso14443a:04a1b2c3d4e5f6"))
        #expect(services.pendingLabOpenURL == URL(string: "https://contoh.test/i/\(token)"))
        #expect(services.pendingLabAddCode == "7K2Q-9XA4")
        let empty = AppServices.inMemory()
        empty.configureLabBackend(arguments: ["Anastrophe", "-ANLabCardReader", "iso14443a:zz"])
        #expect(empty.labCardIdentity == nil && empty.pendingLabOpenURL == nil && empty.pendingLabAddCode == nil)
    }

    @Test func argumenLengkapMenghasilkanTarget() {
        let target = LabBackendTarget(arguments: ["Anastrophe", "-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "d1", "-ANLabSite", "s1"])
        #expect(target?.baseURL == URL(string: "http://127.0.0.1:8080"))
        #expect(target?.deviceID == "d1")
        #expect(target?.siteID == "s1")
    }

    @Test(arguments: [
        ["-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "d1"],
        ["-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "d1", "-ANLabSite"],
        ["-ANLabBackend", "ftp://127.0.0.1", "-ANLabDevice", "d1", "-ANLabSite", "s1"],
        ["-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "-ANLabSite", "s1"],
    ])
    func argumenTidakLengkapDiabaikan(arguments: [String]) {
        #expect(LabBackendTarget(arguments: arguments) == nil)
    }

    @Test func kartuLabDariArgumen() {
        // ADR-0031: enrolment lab memakai identitas kartu yang sama dengan devseed -lab-card.
        let base = ["Anastrophe", "-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "d1", "-ANLabSite", "s1"]
        #expect(LabBackendTarget(arguments: base + ["-ANLabCard", "iso15693:e004010203040506"])?.card.hex == "e004010203040506")
        #expect(LabBackendTarget(arguments: base)?.card == LabBackendTarget.defaultCard)
        #expect(LabBackendTarget(arguments: base + ["-ANLabCard", "iso14443a:zz"]) == nil)
    }

    @Test func undanganLabDariArgumen() {
        // ADR-0033: lab bisa mendaftar dengan undangan sebagai pengganti kartu lab.
        let token = String(repeating: "A", count: 42) + "w"
        let base = ["Anastrophe", "-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "d1", "-ANLabSite", "s1"]
        #expect(LabBackendTarget(arguments: base + ["-ANLabInvite", token])?.invitation == token)
        #expect(LabBackendTarget(arguments: base)?.invitation == nil)
        #expect(LabBackendTarget(arguments: base + ["-ANLabInvite", "pendek"]) == nil)
        #expect(LabBackendTarget(arguments: base + ["-ANLabInvite"]) == nil)
        // Review akhir M1: alfabet base64url memuat "-", jadi ±1 dari 64 token diawali "-".
        let dashed = "-" + String(repeating: "A", count: 41) + "w"
        #expect(LabBackendTarget(arguments: base + ["-ANLabInvite", dashed])?.invitation == dashed)
    }

    @Test func isianFormDirapikan() {
        // ID biasanya ditempel dari terminal, sering dengan spasi atau baris baru di ujung.
        let target = LabBackendTarget(url: " http://127.0.0.1:8080\n", deviceID: " d1\n", siteID: "s1 ")
        #expect(target?.baseURL.host() == "127.0.0.1")
        #expect(target?.deviceID == "d1")
        #expect(target?.siteID == "s1")
        #expect(LabBackendTarget(url: "http://127.0.0.1:8080", deviceID: " ", siteID: "s1") == nil)
    }
}

@MainActor
@Suite("Provisioning lab saat peluncuran (DEBUG)")
struct LabBackendLaunchTests {
    let arguments = ["Anastrophe", "-ANLabBackend", "http://127.0.0.1:8080", "-ANLabDevice", "d1", "-ANLabSite", "s1"]
    let target = LabBackendTarget(url: "http://127.0.0.1:8080", deviceID: "d1", siteID: "s1")!

    @Test func provisioningPeluncuranBerjalanSekali() async throws {
        let services = AppServices.inMemory()
        services.configureLabBackend(arguments: arguments)
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16)), "application/json"),
        ])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == localized("lab.imported"))
        #expect(try await services.cards.all().map(\.siteName) == ["Gedung Lab"])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == nil)
        #expect(transport.paths.count == 3)  // tidak ada enrolment kedua
    }

    @Test func provisioningPeluncuranDenganUndangan() async throws {
        // ADR-0033: -ANLabInvite menggantikan kartu lab di body enrolment.
        let token = String(repeating: "A", count: 42) + "w"
        let services = AppServices.inMemory()
        services.configureLabBackend(arguments: arguments + ["-ANLabInvite", token])
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16)), "application/json"),
        ])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == localized("lab.imported"))
        let enrolment = try #require(transport.bodies[1])
        let body = try #require(try JSONSerialization.jsonObject(with: enrolment) as? [String: String])
        #expect(body["device_id"] == "d1" && body["invitation"] == token)
        #expect(body.keys.sorted() == ["device_id", "invitation", "provisioning_key_hash"])
    }

    @Test func provisioningPeluncuranDilewatiBilaSudahAdaKartu() async throws {
        // Argumen skema Xcode bertahan antar-Run; tanpa ini setiap peluncuran menambah kartu.
        let services = AppServices.inMemory()
        try await services.cards.add(Card(id: UUID(), name: "Lama", siteName: "Gedung Lab", zones: [], status: .active, credentials: [:], notAfter: nil))
        services.configureLabBackend(arguments: arguments)
        let transport = SequenceTransport([])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == localized("lab.backend.skipped"))
        #expect(transport.paths.isEmpty)
        #expect(try await services.cards.all().count == 1)
    }

    /// Kartu lab dengan record yang bisa diperpanjang (renewalURL terisi).
    func renewableCard(in services: AppServices) async throws -> Card {
        let credentialID = Data(repeating: 0x5E, count: 16)
        _ = try services.keys.createKey(for: credentialID)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: Date(timeIntervalSince1970: 1_794_096_000),
                                                   groupKeys: ["a1a2a3a4a5a6a7a8": [P256.Signing.PrivateKey().publicKey.x963Representation]], renewalURL: URL(string: "http://127.0.0.1:8080")))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: ["Pintu Lab"], status: .active, credentials: [.ble: credentialID], notAfter: Date(timeIntervalSince1970: 1_794_096_000))
        try await services.cards.add(card)
        return card
    }

    var renewalChallengeReply: (status: Int, body: String, contentType: String) {
        (201, #"{"nonce":"\#(Data(repeating: 0x4E, count: 32).base64EncodedString())","expires_at":"2026-11-09T00:02:00Z"}"#, "application/json")
    }

    @Test func perpanjanganLabSaatPeluncuran() async throws {
        let services = AppServices.inMemory()
        _ = try await renewableCard(in: services)
        services.configureLabBackend(arguments: ["Anastrophe", "-ANLabRenew"])
        let transport = SequenceTransport([
            renewalChallengeReply,
            (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16), notAfter: "2026-11-16T00:00:00Z", notBefore: "2026-11-09T00:00:00Z"), "application/json"),
        ])
        #expect(await services.runPendingLabRenewal(transport: transport) == localized("lab.renewed"))
        #expect(try await services.cards.all().first?.notAfter == Date(timeIntervalSince1970: 1_794_787_200))
        #expect(await services.runPendingLabRenewal(transport: transport) == nil)  // sekali per peluncuran
    }

    @Test func perpanjanganLabGagalMenampilkanKode() async throws {
        let services = AppServices.inMemory()
        let card = try await renewableCard(in: services)
        let transport = SequenceTransport([(409, #"{"type":"CRED-NOT-RENEWABLE","status":409}"#, "application/problem+json")])
        #expect(await services.labRenew(card: card, transport: transport) == "\(localized("lab.renew_failed")) (CRED-NOT-RENEWABLE)")
    }

    @Test func tanpaArgumenTidakAdaProvisioning() async {
        let services = AppServices.inMemory()
        services.configureLabBackend(arguments: ["Anastrophe"])
        let transport = SequenceTransport([])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == nil)
        #expect(transport.paths.isEmpty)
    }

    @Test func batasKartuDariServerMenjadiPesanBatas() async throws {
        let services = AppServices.inMemory()
        let transport = SequenceTransport([configBody(), (409, #"{"type":"ENR-LIMIT","status":409}"#, "application/problem+json")])
        #expect(await services.provisionFromLabBackend(target, channel: .ble, transport: transport) == localized("lab.limit"))
        #expect(try await services.cards.all().isEmpty)
    }

    @Test func kodeProblemDitampilkanUntukDiagnosis() async {
        let services = AppServices.inMemory()
        let transport = SequenceTransport([
            configBody(),
            (201, #"{"enrollment_id":"e1","status":"PROVISIONING"}"#, "application/json"),
            (400, #"{"type":"ENR-INVALID-KEY","status":400}"#, "application/problem+json"),
        ])
        let message = await services.provisionFromLabBackend(target, channel: .ble, transport: transport)
        #expect(message == "\(localized("lab.backend.failed")) (ENR-INVALID-KEY)")
    }

    @Test func kanalTidakAktifDiBackendMemberiPesan() async {
        let services = AppServices.inMemory()
        let message = await services.provisionFromLabBackend(target, channel: .nfcHCE, transport: SequenceTransport([configBody(["ble"])]))
        #expect(message == localized("lab.backend.channel_disabled"))
    }

    @Test func provisioningPeluncuranDilewatiBilaPenyimpananGagal() async {
        // Review lab I1: tanpa penyimpanan, kartu dari server pasti ditolak lokal.
        let services = AppServices.storageUnavailable()
        services.configureLabBackend(arguments: arguments)
        let transport = SequenceTransport([])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == nil)
        #expect(transport.paths.isEmpty)
    }

    @Test func backendTidakTerjangkauMemberiPesanGagal() async {
        let services = AppServices.inMemory()
        let message = await services.provisionFromLabBackend(target, channel: .ble, transport: SequenceTransport([]))
        // Review lab M4c: kode URLError membantu diagnosis (mis. -1004 = host tak terjangkau).
        #expect(message == "\(localized("lab.backend.failed")) (URLError -1004)")
    }
}

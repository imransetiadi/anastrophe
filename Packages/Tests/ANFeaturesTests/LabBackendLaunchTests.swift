import ANCore
import ANNetworking
import Foundation
import Testing
@testable import ANFeatures

@Suite("Target backend lab (argumen peluncuran DEBUG)")
struct LabBackendTargetTests {
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
            (201, #"{"enrollment_id":"e1"}"#, "application/json"),
            (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16)), "application/json"),
        ])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == localized("lab.imported"))
        #expect(try await services.cards.all().map(\.siteName) == ["Gedung Lab"])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == nil)
        #expect(transport.paths.count == 2)  // tidak ada enrolment kedua
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

    @Test func tanpaArgumenTidakAdaProvisioning() async {
        let services = AppServices.inMemory()
        services.configureLabBackend(arguments: ["Anastrophe"])
        let transport = SequenceTransport([])
        #expect(await services.runPendingLabBackendProvisioning(transport: transport) == nil)
        #expect(transport.paths.isEmpty)
    }

    @Test func batasKartuDariServerMenjadiPesanBatas() async throws {
        let services = AppServices.inMemory()
        let transport = SequenceTransport([(409, #"{"type":"ENR-LIMIT","status":409}"#, "application/problem+json")])
        #expect(await services.provisionFromLabBackend(target, channel: .ble, transport: transport) == localized("lab.limit"))
        #expect(try await services.cards.all().isEmpty)
    }

    @Test func kodeProblemDitampilkanUntukDiagnosis() async {
        let services = AppServices.inMemory()
        let transport = SequenceTransport([
            (201, #"{"enrollment_id":"e1"}"#, "application/json"),
            (400, #"{"type":"ENR-INVALID-CHANNEL","status":400}"#, "application/problem+json"),
        ])
        let message = await services.provisionFromLabBackend(target, channel: .nfcHCE, transport: transport)
        #expect(message == "\(localized("lab.backend.failed")) (ENR-INVALID-CHANNEL)")
    }

    @Test func backendTidakTerjangkauMemberiPesanGagal() async {
        let services = AppServices.inMemory()
        let message = await services.provisionFromLabBackend(target, channel: .ble, transport: SequenceTransport([]))
        #expect(message == localized("lab.backend.failed"))
    }
}

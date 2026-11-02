import ANCore
import ANCrypto
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@MainActor
@Suite("Laporan diagnostik tanpa rahasia (FR-63, TC-PRIV-06)")
struct DiagnosticsReportTests {
    let notAfter = Date(timeIntervalSince1970: 1_794_096_000)  // 2026-11-08T00:00:00Z

    @Test func laporanMemuatBidangYangDiizinkan() {
        let input = DiagnosticsInput(appVersion: "0.1.0", build: "7", osVersion: "Version 26.1 (Build 23B)", locale: "id_ID",
                                     channels: [.nfcHCE: .notEligible, .ble: .bluetoothOff], serviceConfigured: true, storageAvailable: true,
                                     cards: [CardSummary(status: .active, channels: [.ble], notAfter: notAfter)])
        let text = DiagnosticsReport.text(input)
        for line in ["app: 0.1.0 (7)", "ios: Version 26.1 (Build 23B)", "bahasa: id_ID", "kanal nfcHCE: notEligible", "kanal ble: bluetoothOff",
                     "penyimpanan: ok", "layanan: ya", "kartu: 1", "kartu 1: active, ble, berlaku sampai 2026-11-08"] {
            #expect(text.contains(line), "tanpa baris \(line)")
        }
    }

    @Test func laporanTanpaKartu() {
        let input = DiagnosticsInput(appVersion: "0.1.0", build: "7", osVersion: "26.1", locale: "en_US", channels: [:], serviceConfigured: false,
                                     storageAvailable: true, cards: [])
        let text = DiagnosticsReport.text(input)
        #expect(text.contains("kartu: 0"))
        #expect(text.contains("layanan: tidak"))
    }

    @Test func laporanTanpaRahasia() async throws {
        // Review Focus 1: store berisi semua rahasia, laporan tidak memuat satu pun.
        let services = AppServices.inMemory(events: [.waitingForReader], apiBaseURL: URL(string: "https://api.rahasia.test/v1"))
        let credentialID = Data(repeating: 0x5E, count: 16)
        let serverCardID = "6f1c2a9e-0000-4000-8000-0000000000aa"
        let token = Data(repeating: 0x31, count: 32)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: notAfter, groupKeys: [:],
                                                   renewalURL: URL(string: "https://api.rahasia.test"), serverCardID: serverCardID))
        try services.statusTokens.save(token, forCard: serverCardID)
        try await services.cards.add(Card(id: UUID(), name: "Menara Rahasia", siteName: "Menara Rahasia", zones: ["Lobi Rahasia"], status: .active,
                                          credentials: [.ble: credentialID], notAfter: notAfter))
        try await services.cards.add(Card(id: UUID(), name: "Tanpa Kanal", siteName: "Gedung Lain", zones: [], status: .suspended, credentials: [:], notAfter: nil))
        let deviceID = try services.deviceIdentity.deviceID()
        let text = DiagnosticsReport.text(await services.diagnosticsInput())
        let secrets = [credentialID.hexString, credentialID.hexString.uppercased(), credentialID.base64EncodedString(), serverCardID, deviceID,
                       token.hexString, token.base64EncodedString(), "Menara Rahasia", "Gedung Lain", "Lobi Rahasia", "rahasia.test"]
        for secret in secrets {
            #expect(!text.contains(secret), "laporan memuat \(secret)")
        }
        #expect(text.contains("kartu: 2"))
        #expect(text.contains("layanan: ya"))
        #expect(text.contains("suspended, -, tanpa masa berlaku"))  // kartu tanpa kanal dan tanpa masa berlaku
    }

    @Test func laporanSaatPenyimpananGagal() async {
        // Review akhir #2: penyimpanan gagal tidak boleh terlihat seperti instalasi baru tanpa kartu.
        let services = AppServices.storageUnavailable(apiBaseURL: URL(string: "https://api.contoh.test"))
        let text = DiagnosticsReport.text(await services.diagnosticsInput())
        #expect(text.contains("penyimpanan: gagal"))
        #expect(text.contains("kartu: tidak terbaca"))
        #expect(text.contains("layanan: ya"))
        #expect(!text.contains("kartu: 0"))
    }

    @Test func laporanSaatKartuGagalDibaca() async {
        let services = AppServices(cards: ThrowingCardStore(), keys: DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory()),
                                   records: KeychainCredentialRecordStore(store: InMemorySecretStore()), availability: { [.ble: .available] },
                                   launcher: ScriptedPresentationLauncher(events: [.cancelled], finishes: true), foreground: ForegroundState(),
                                   authenticator: ImmediateAuthenticator(), tapHistory: InMemoryTapHistoryStore())
        let text = DiagnosticsReport.text(await services.diagnosticsInput())
        #expect(text.contains("penyimpanan: ok"))
        #expect(text.contains("kartu: tidak terbaca"))
        #expect(!text.contains("kartu: 0"))
    }
}

/// Store kartu yang selalu gagal dibaca.
struct ThrowingCardStore: CardStore {
    func all() async throws -> [Card] { throw ANError.internalError }
    func add(_ card: Card) async throws { throw ANError.internalError }
    func update(_ card: Card) async throws { throw ANError.internalError }
    func remove(id: UUID) async throws { throw ANError.internalError }
}

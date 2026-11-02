import ANCore
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

/// Store kartu yang gagal dibaca (uji: pembersihan instal ulang tidak boleh berjalan).
private struct UnreadableCardStore: CardStore {
    func all() async throws -> [Card] { throw ANError.internalError }
    func add(_ card: Card) async throws { throw ANError.internalError }
    func update(_ card: Card) async throws { throw ANError.internalError }
    func remove(id: UUID) async throws { throw ANError.internalError }
}

@MainActor
@Suite("Pembersihan instal ulang (FR-43, ADR-0053)")
struct InstallCleanupTests {
    private func services(cards: any CardStore, secrets: InMemorySecretStore, marker: URL) -> AppServices {
        AppServices(
            cards: cards,
            keys: DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory()),
            records: KeychainCredentialRecordStore(store: secrets),
            availability: { [:] },
            launcher: ScriptedPresentationLauncher(events: []),
            foreground: ForegroundState(),
            authenticator: ImmediateAuthenticator(),
            tapHistory: InMemoryTapHistoryStore(),
            statusTokens: KeychainStatusTokenStore(store: secrets),
            deviceIdentity: KeychainDeviceIdentityStore(store: secrets, installMarker: marker)
        )
    }

    private func leftovers() throws -> InMemorySecretStore {
        let secrets = InMemorySecretStore()
        for key in ["cred.key.aa", "cred.record.aa", "status-token.x", "device-id"] {
            try secrets.set(Data([1]), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        }
        return secrets
    }

    @Test func instalUlangMembersihkanSisa() async throws {
        let secrets = try leftovers()
        let marker = temporaryDirectory().appending(path: "installed")
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        await services(cards: cards, secrets: secrets, marker: marker).prepareInstall()
        #expect(secrets.storedKeyCount == 0)
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func kartuAdaTidakDibersihkan() async throws {
        let secrets = try leftovers()
        let marker = temporaryDirectory().appending(path: "installed")
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        try await cards.add(Card(id: UUID(), name: "Lobi", siteName: "Menara Uji", zones: [], status: .active, credentials: [.ble: Data([0xAA])], notAfter: nil))
        await services(cards: cards, secrets: secrets, marker: marker).prepareInstall()
        #expect(secrets.storedKeyCount == 4)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func storeKartuGagalTidakDibersihkan() async throws {
        // Store yang tak terbaca dianggap berisi kartu: lebih baik sisa tertinggal daripada kunci kartu hilang.
        let secrets = try leftovers()
        let marker = temporaryDirectory().appending(path: "installed")
        await services(cards: UnreadableCardStore(), secrets: secrets, marker: marker).prepareInstall()
        #expect(secrets.storedKeyCount == 4)
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}

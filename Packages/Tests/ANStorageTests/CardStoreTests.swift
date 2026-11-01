import ANCore
import Foundation
import SwiftData
import Testing
@testable import ANStorage

func makeCard(_ name: String, credentials: [ChannelKind: Data] = [.ble: Data(repeating: 0xB1, count: 16)], status: CardStatus = .active) -> Card {
    Card(id: UUID(), name: name, siteName: "Menara A", zones: ["Lobi"], status: status, credentials: credentials, notAfter: Date(timeIntervalSince1970: 1_900_000_000))
}

/// Keychain yang selalu gagal dibaca (mis. perangkat terkunci saat diperiksa).
struct FailingSecretStore: SecretStore {
    func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws { throw ANError.internalError }
    func get(_ key: String) throws -> Data? { throw ANError.internalError }
    func delete(_ key: String) throws { throw ANError.internalError }
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "anastrophe-tests-\(UUID().uuidString)")
}

@Suite("Metadata kartu (SDD §5.3, FR-15, FR-38)")
struct CardStoreTests {
    @Test func barisKartuTakTerbacaMembuatAllGagal() async throws {
        // Kontrak yang diandalkan sapu riwayat: all() gagal, bukan mengembalikan daftar sebagian.
        let directory = temporaryDirectory()
        let card = makeCard("Lobi")
        do {
            let store = try SwiftDataCardStore(directory: directory)
            try await store.add(card)
            try await store.add(makeCard("Parkir"))
        }
        do {
            let configuration = ModelConfiguration(schema: Schema([CardEntity.self]), url: directory.appending(path: "cards.store"), cloudKitDatabase: .none)
            let context = ModelContext(try ModelContainer(for: CardEntity.self, configurations: configuration))
            try context.fetch(FetchDescriptor<CardEntity>()).first { $0.name == card.name }?.statusRaw = "status-masa-depan"
            try context.save()
        }
        let reopened = try SwiftDataCardStore(directory: directory)
        await #expect(throws: ANError.invalidData) { try await reopened.all() }
    }

    @Test func kartuKesembilanDitolak() async throws {
        let store = try SwiftDataCardStore(directory: temporaryDirectory())
        for i in 1...8 { try await store.add(makeCard("Kartu \(i)")) }
        await #expect(throws: ANError.cardLimitReached) { try await store.add(makeCard("Kartu 9")) }
        #expect(try await store.all().count == 8)
    }

    @Test func storeDikecualikanDariBackup() throws {
        let directory = temporaryDirectory()
        _ = try SwiftDataCardStore(directory: directory)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func dataBertahanLintasInstance() async throws {
        let directory = temporaryDirectory()
        let card = makeCard("Lobi", credentials: [.ble: Data(repeating: 0xB1, count: 16), .nfcHCE: Data(repeating: 0xB2, count: 16)])
        try await SwiftDataCardStore(directory: directory).add(card)
        #expect(try await SwiftDataCardStore(directory: directory).all() == [card])
    }

    @Test func updateDanRemove() async throws {
        let store = try SwiftDataCardStore(directory: temporaryDirectory())
        var card = makeCard("Parkir")
        try await store.add(card)
        card.status = .suspended
        try await store.update(card)
        #expect(try await store.all().first?.status == .suspended)
        try await store.remove(id: card.id)
        #expect(try await store.all().isEmpty)
    }

    @Test func kunciHilangMenandaiPerluDipindahkan() throws {
        // Review Focus 3: metadata ada tetapi kunci tidak (restore/passcode dimatikan).
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        let withKey = makeCard("Lobi", credentials: [.ble: Data(repeating: 0x01, count: 16)])
        _ = try keys.createKey(for: Data(repeating: 0x01, count: 16))
        let withoutKey = makeCard("Parkir", credentials: [.nfcHCE: Data(repeating: 0x02, count: 16)])
        let seOnly = makeCard("Kantor", credentials: [.nfcSE: Data(repeating: 0x03, count: 16)])
        let revoked = makeCard("Lama", credentials: [.ble: Data(repeating: 0x04, count: 16)], status: .revoked)
        let renewing = makeCard("Gym", credentials: [.ble: Data(repeating: 0x05, count: 16)], status: .needsRenewal)

        let result = RestoreCheck.reconcile([withKey, withoutKey, seOnly, revoked, renewing], keys: keys)
        #expect(result.map(\.status) == [.active, .needsTransfer, .active, .revoked, .needsTransfer])
    }

    @Test func errorKeychainTidakMenandaiPerluDipindahkan() {
        // Minor 6: "tidak bisa dibaca sekarang" ≠ "kunci hilang".
        let card = makeCard("Lobi", credentials: [.ble: Data(repeating: 0x07, count: 16)])
        let keys = DeviceKeyStore(store: FailingSecretStore(), factory: SoftwareKeyFactory())
        #expect(RestoreCheck.reconcile([card], keys: keys).first?.status == .active)
    }

    @Test func perluDipindahkanPulihBilaKunciKembali() throws {
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        let credentialID = Data(repeating: 0x08, count: 16)
        _ = try keys.createKey(for: credentialID)
        let card = makeCard("Lobi", credentials: [.ble: credentialID], status: .needsTransfer)
        #expect(RestoreCheck.reconcile([card], keys: keys).first?.status == .active)
    }

    @Test(arguments: [CardStatus.suspended, .pendingApproval, .revoked])
    func statusPemblokirDariServerDidahulukan(status: CardStatus) {
        // Memindahkan kartu tidak menyelesaikan status yang ditetapkan pengelola gedung.
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        let card = makeCard("Kantor", credentials: [.ble: Data(repeating: 0x06, count: 16)], status: status)
        #expect(RestoreCheck.reconcile([card], keys: keys).first?.status == status)
    }

    @Test func pembaruanTerarahMemakaiNilaiTerbaru() async throws {
        // Review akhir siklus hidup M4: penulis lain (mis. perpanjangan) tidak tertimpa salinan basi.
        let store = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung", siteName: "Gedung", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await store.add(card)
        var renewed = card
        renewed.notAfter = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.update(renewed)
        let changed = try await store.update(id: card.id) { current in
            current.status = .suspended
            return true
        }
        let stored = try #require(try await store.all().first)
        #expect(changed && stored.status == .suspended && stored.notAfter == renewed.notAfter)
    }
}

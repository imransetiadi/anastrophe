import ANCore
import Foundation
import Testing
@testable import ANStorage

@Suite("Identitas perangkat (ADR-0045)")
struct DeviceIdentityStoreTests {
    @Test func idPerangkatDibuatSekaliDanStabil() throws {
        let secrets = InMemorySecretStore()
        let marker = temporaryDirectory().appending(path: "installed")
        let store = KeychainDeviceIdentityStore(store: secrets, installMarker: marker)
        let first = try store.deviceID()
        #expect(try store.deviceID() == first)
        #expect(UUID(uuidString: first) != nil)
        #expect(first == first.lowercased())
        #expect(secrets.accessibility(for: KeychainDeviceIdentityStore.key) == .afterFirstUnlockThisDeviceOnly)
        // Peluncuran berikutnya (instance baru, penanda masih ada) memakai id yang sama.
        #expect(try KeychainDeviceIdentityStore(store: secrets, installMarker: marker).deviceID() == first)
    }

    @Test func instalasiBaruMembuatIDBaru() throws {
        // FR-43: instal ulang menghapus kontainer app (penanda), tetapi item Keychain bisa tersisa.
        let secrets = InMemorySecretStore()
        let marker = temporaryDirectory().appending(path: "installed")
        let first = try KeychainDeviceIdentityStore(store: secrets, installMarker: marker).deviceID()
        try FileManager.default.removeItem(at: marker)
        let second = try KeychainDeviceIdentityStore(store: secrets, installMarker: marker).deviceID()
        #expect(second != first)
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        #expect(try marker.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func instalUlangMembersihkanSisaKeychain() throws {
        // FR-43 (ADR-0053): penanda hilang dan tidak ada kartu → semua sisa Keychain dihapus sebelum dipakai.
        let secrets = InMemorySecretStore()
        let marker = temporaryDirectory().appending(path: "installed")
        for key in ["cred.key.aa", "cred.record.aa", "status-token.x", KeychainDeviceIdentityStore.key] {
            try secrets.set(Data([1]), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        }
        let store = KeychainDeviceIdentityStore(store: secrets, installMarker: marker)
        #expect(try store.purgeLeftoversIfFreshInstall(hasCards: false))
        #expect(secrets.storedKeyCount == 0)
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        #expect(try marker.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let id = try store.deviceID()
        #expect(UUID(uuidString: id) != nil)
        #expect(try store.deviceID() == id)
        #expect(try store.purgeLeftoversIfFreshInstall(hasCards: false) == false)
        #expect(try secrets.get(KeychainDeviceIdentityStore.key) != nil)
    }

    @Test func kartuMasihAdaTidakDibersihkan() throws {
        // Pembaruan dari build tanpa penanda: kunci kartu yang masih ada tidak boleh hilang.
        let secrets = InMemorySecretStore()
        let marker = temporaryDirectory().appending(path: "installed")
        try secrets.set(Data([1]), for: "cred.key.aa", accessibility: .whenPasscodeSetThisDeviceOnly)
        let store = KeychainDeviceIdentityStore(store: secrets, installMarker: marker)
        #expect(try store.purgeLeftoversIfFreshInstall(hasCards: true) == false)
        #expect(try secrets.get("cred.key.aa") == Data([1]))
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func penandaAdaTidakDibersihkan() throws {
        let secrets = InMemorySecretStore()
        let marker = temporaryDirectory().appending(path: "installed")
        let store = KeychainDeviceIdentityStore(store: secrets, installMarker: marker)
        _ = try store.deviceID()  // membuat penanda
        try secrets.set(Data([1]), for: "cred.key.aa", accessibility: .whenPasscodeSetThisDeviceOnly)
        #expect(try store.purgeLeftoversIfFreshInstall(hasCards: false) == false)
        #expect(try secrets.get("cred.key.aa") == Data([1]))
    }

    @Test func gagalHapusTidakMembuatPenanda() throws {
        // Penanda hanya dibuat sesudah penghapusan berhasil, agar dicoba lagi di peluncuran berikutnya.
        let marker = temporaryDirectory().appending(path: "installed")
        let store = KeychainDeviceIdentityStore(store: DeleteAllFailingSecretStore(), installMarker: marker)
        #expect(throws: (any Error).self) { try store.purgeLeftoversIfFreshInstall(hasCards: false) }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}

/// Store yang gagal menghapus semua item (uji pembersihan instal ulang).
private struct DeleteAllFailingSecretStore: SecretStore {
    func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws {}
    func get(_ key: String) throws -> Data? { nil }
    func delete(_ key: String) throws {}
    func deleteAll() throws { throw ANError.internalError }
}

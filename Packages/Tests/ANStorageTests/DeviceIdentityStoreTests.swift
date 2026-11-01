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
}

import Foundation
import Security
import Testing
@testable import ANStorage

/// Keychain palsu berbasis dictionary dengan injeksi kegagalan tulis/hapus. Item dikunci per service +
/// account; query hapus tanpa account menghapus semua item service itu (seperti `SecItemDelete`).
final class FakeKeychain: KeychainAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var failWrites = false
    var failDeletes = false

    private func key(_ query: [CFString: Any]) -> String {
        "\(query[kSecAttrService] as! String)|\(query[kSecAttrAccount] as! String)"
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        lock.withLock {
            if failWrites { return errSecIO }
            guard items[key(attributes)] == nil else { return errSecDuplicateItem }
            items[key(attributes)] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus {
        lock.withLock {
            if failWrites { return errSecIO }
            guard items[key(query)] != nil else { return errSecItemNotFound }
            items[key(query)] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func copy(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        lock.withLock { items[key(query)].map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil) }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        lock.withLock {
            if failDeletes { return errSecIO }
            // Store hanya menyimpan generic password; kelas lain tidak cocok dengan item apa pun (review akhir
            // ADR-0053: kelas yang salah membuat pembersihan diam-diam tidak menghapus apa-apa).
            guard (query[kSecClass] as? String) == (kSecClassGenericPassword as String) else { return errSecItemNotFound }
            guard query[kSecAttrAccount] == nil else {
                return items.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess
            }
            // Tanpa service, SecItemDelete menghapus semua item kelas itu milik app.
            let prefix = (query[kSecAttrService] as? String).map { "\($0)|" } ?? ""
            let matching = items.keys.filter { $0.hasPrefix(prefix) }
            matching.forEach { items.removeValue(forKey: $0) }
            return matching.isEmpty ? errSecItemNotFound : errSecSuccess
        }
    }

    var count: Int { lock.withLock { items.count } }
}

@Suite("Keychain (temuan review I6)")
struct KeychainSecretStoreTests {
    @Test func gagalTulisTidakMenghapusNilaiLama() throws {
        // Counter yang hilang akan mulai lagi dari 1 (anomali TC-PROTO-11).
        let keychain = FakeKeychain()
        let store = KeychainSecretStore(service: "test", keychain: keychain)
        try store.set(Data([0, 0, 0, 7]), for: "counter", accessibility: .afterFirstUnlockThisDeviceOnly)
        keychain.failWrites = true
        #expect(throws: (any Error).self) {
            try store.set(Data([0, 0, 0, 8]), for: "counter", accessibility: .afterFirstUnlockThisDeviceOnly)
        }
        #expect(try store.get("counter") == Data([0, 0, 0, 7]))
    }

    @Test func tulisUlangMemperbaruiNilai() throws {
        let store = KeychainSecretStore(service: "test", keychain: FakeKeychain())
        try store.set(Data([1]), for: "k", accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data([2]), for: "k", accessibility: .afterFirstUnlockThisDeviceOnly)
        #expect(try store.get("k") == Data([2]))
        try store.delete("k")
        #expect(try store.get("k") == nil)
    }

    @Test func hapusSemuaHanyaServiceIni() throws {
        // ADR-0053: instal ulang menghapus semua item service app, tidak menyentuh service lain.
        let keychain = FakeKeychain()
        let app = KeychainSecretStore(service: "a", keychain: keychain)
        let other = KeychainSecretStore(service: "b", keychain: keychain)
        try app.set(Data([1]), for: "cred.key.aa", accessibility: .whenPasscodeSetThisDeviceOnly)
        try app.set(Data([2]), for: "status-token.x", accessibility: .afterFirstUnlockThisDeviceOnly)
        try other.set(Data([3]), for: "cred.key.aa", accessibility: .afterFirstUnlockThisDeviceOnly)
        try app.deleteAll()
        #expect(try app.get("cred.key.aa") == nil)
        #expect(try app.get("status-token.x") == nil)
        #expect(try other.get("cred.key.aa") == Data([3]))
        #expect(keychain.count == 1)
    }

    @Test func hapusSemuaKosongTidakGagal() throws {
        try KeychainSecretStore(service: "a", keychain: FakeKeychain()).deleteAll()
    }

    @Test func hapusSemuaGagalDilaporkan() throws {
        let keychain = FakeKeychain()
        let store = KeychainSecretStore(service: "a", keychain: keychain)
        try store.set(Data([1]), for: "k", accessibility: .afterFirstUnlockThisDeviceOnly)
        keychain.failDeletes = true
        #expect(throws: (any Error).self) { try store.deleteAll() }
    }
}

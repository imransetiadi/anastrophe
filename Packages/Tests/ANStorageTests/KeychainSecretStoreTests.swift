import Foundation
import Security
import Testing
@testable import ANStorage

/// Keychain palsu berbasis dictionary dengan injeksi kegagalan tulis.
final class FakeKeychain: KeychainAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var failWrites = false

    private func key(_ query: [CFString: Any]) -> String { query[kSecAttrAccount] as! String }

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
        lock.withLock { items.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess }
    }
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
}

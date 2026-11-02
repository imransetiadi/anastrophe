import ANCore
import Foundation
import Security

/// Kelas proteksi item rahasia; keduanya `…ThisDeviceOnly` (tidak ikut backup).
public enum SecretAccessibility: Sendable {
    /// Token sesi, sertifikat, kunci publik reader group, counter (SDD §5.3).
    case afterFirstUnlockThisDeviceOnly
    /// Blob kunci kredensial; hilang bila passcode dimatikan (ADR-0009).
    case whenPasscodeSetThisDeviceOnly

    var attribute: CFString {
        switch self {
        case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

/// Penyimpanan rahasia (Keychain), di balik protokol agar bisa di-mock.
public protocol SecretStore: Sendable {
    func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws
    func get(_ key: String) throws -> Data?
    func delete(_ key: String) throws
    /// Menghapus semua item app di store ini (instal ulang, ADR-0053).
    func deleteAll() throws
}

/// Kebijakan kunci kredensial in-app (ADR-0009, SDD §5.3): Secure Enclave,
/// hanya bila passcode aktif, tidak ikut backup, wajib kehadiran pengguna.
public enum CredentialKeyPolicy {
    public static var accessibility: CFString { kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly }
    public static let accessControlFlags: SecAccessControlCreateFlags = [.privateKeyUsage, .userPresence]

    public static func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(nil, accessibility, accessControlFlags, &error) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? ANError.internalError
        }
        return control
    }
}

/// Store untuk test dan preview.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: (data: Data, accessibility: SecretAccessibility)] = [:]

    public init() {}

    public func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws {
        lock.withLock { items[key] = (data, accessibility) }
    }

    public func get(_ key: String) throws -> Data? { lock.withLock { items[key]?.data } }
    public func delete(_ key: String) throws { _ = lock.withLock { items.removeValue(forKey: key) } }
    public func deleteAll() throws { lock.withLock { items.removeAll() } }

    /// Jumlah item tersimpan, untuk memeriksa kunci yatim di test.
    public var storedKeyCount: Int { lock.withLock { items.count } }

    /// Kelas proteksi item, untuk pemeriksaan di test.
    public func accessibility(for key: String) -> SecretAccessibility? { lock.withLock { items[key]?.accessibility } }
}

/// Operasi Keychain mentah, di balik protokol agar urutan tulis bisa diuji.
protocol KeychainAPI: Sendable {
    func add(_ attributes: [CFString: Any]) -> OSStatus
    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus
    func copy(_ query: [CFString: Any]) -> (OSStatus, Data?)
    func delete(_ query: [CFString: Any]) -> OSStatus
}

struct SystemKeychain: KeychainAPI {
    func add(_ attributes: [CFString: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus { SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }

    func copy(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func delete(_ query: [CFString: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// Keychain generic password.
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let keychain: any KeychainAPI

    public init(service: String = "app.anastrophe") {
        self.init(service: service, keychain: SystemKeychain())
    }

    init(service: String, keychain: any KeychainAPI) {
        self.service = service
        self.keychain = keychain
    }

    private func query(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    /// Perbarui di tempat; tambah hanya bila belum ada. Tidak pernah hapus-lalu-tambah,
    /// agar tulis yang gagal tidak menghilangkan nilai lama (mis. counter, TC-PROTO-11).
    public func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws {
        let changes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: accessibility.attribute]
        let status = keychain.update(query(key), changes)
        guard status == errSecItemNotFound else { return try check(status) }
        try check(keychain.add(query(key).merging(changes) { $1 }))
    }

    public func get(_ key: String) throws -> Data? {
        var request = query(key)
        request[kSecReturnData] = true
        let (status, data) = keychain.copy(request)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return data
    }

    public func delete(_ key: String) throws {
        let status = keychain.delete(query(key))
        if status != errSecItemNotFound { try check(status) }
    }

    /// Satu `SecItemDelete` dengan kelas + service tanpa account: semua item service ini terhapus, service lain
    /// tidak tersentuh (ADR-0053). Keychain yang sudah kosong bukan galat.
    public func deleteAll() throws {
        let status = keychain.delete([kSecClass: kSecClassGenericPassword, kSecAttrService: service])
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

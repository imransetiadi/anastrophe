import ANCore
import CryptoKit
import Foundation
import Security

/// Token baca status kartu (ADR-0037): 32 byte acak per card instance, dibuat app. Server hanya
/// menerima dan menyimpan SHA-256-nya; token mentah hanya dikirim sebagai bearer saat membaca status.
public enum StatusToken {
    public static let length = 32

    public static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else { throw ANError.internalError }
        return Data(bytes)
    }

    public static func hash(_ token: Data) -> Data { Data(SHA256.hash(data: token)) }
}

/// Rahasia enrolment (ADR-0040): 32 byte acak per enrolment, hanya di memori selama alur enrolment.
/// Server menerima SHA-256-nya saat enrolment dan rahasianya sebagai bearer saat kredensial pertama.
public enum ProvisioningSecret {
    public static func generate() throws -> Data { try StatusToken.generate() }
    public static func hash(_ secret: Data) -> Data { StatusToken.hash(secret) }
}

/// Penyimpanan token baca status per id card instance server, di balik protokol agar bisa di-mock.
public protocol StatusTokenStore: Sendable {
    func token(forCard id: String) throws -> Data?
    func save(_ token: Data, forCard id: String) throws
    func delete(forCard id: String) throws
}

/// Keychain `afterFirstUnlockThisDeviceOnly` (SDD §5.3): terbaca tanpa kehadiran pengguna, sehingga
/// pemeriksaan status tidak memunculkan Face ID atau passcode, dan tidak ikut backup.
public struct KeychainStatusTokenStore: StatusTokenStore {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    static func key(_ id: String) -> String { "status-token.\(id.lowercased())" }

    public func token(forCard id: String) throws -> Data? { try store.get(Self.key(id)) }

    public func save(_ token: Data, forCard id: String) throws {
        guard token.count == StatusToken.length else { throw ANError.invalidData }
        try store.set(token, for: Self.key(id), accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    public func delete(forCard id: String) throws { try store.delete(Self.key(id)) }
}

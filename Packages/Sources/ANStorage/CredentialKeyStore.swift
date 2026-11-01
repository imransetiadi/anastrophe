import ANCore
import ANCrypto
import CryptoKit
import Foundation

/// Kunci kredensial per `cred_id` (kanal N-HCE dan B).
public protocol CredentialKeyStore: Sendable {
    /// Membuat kunci baru; mengembalikan kunci publik x963 (65 B).
    func createKey(for credentialID: Data) throws -> Data
    func signer(for credentialID: Data, context: AuthorizedContext) throws -> any CredentialSigner
    /// `false` bila kunci tidak ada; melempar error bila Keychain tidak bisa dibaca.
    func hasKey(for credentialID: Data) throws -> Bool
    func deleteKey(for credentialID: Data) throws
    /// Memindahkan kunci ke `cred_id` yang ditetapkan server (blob terikat perangkat, kunci
    /// privat tidak pernah diekspor).
    func moveKey(from: Data, to: Data) throws
}

/// Pembuat kunci tanda tangan. Live: Secure Enclave; test/preview: perangkat lunak.
public protocol SigningKeyFactory: Sendable {
    func makeKey() throws -> (publicKey: Data, blob: Data)
    func signer(blob: Data, context: AuthorizedContext) throws -> any CredentialSigner
}

/// Kunci di Secure Enclave dengan `CredentialKeyPolicy` (ADR-0009). `blob` adalah
/// `dataRepresentation` yang terikat perangkat, bukan kunci privat.
public struct SecureEnclaveKeyFactory: SigningKeyFactory {
    public init() {}

    public func makeKey() throws -> (publicKey: Data, blob: Data) {
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: CredentialKeyPolicy.makeAccessControl())
        return (key.publicKey.x963Representation, key.dataRepresentation)
    }

    public func signer(blob: Data, context: AuthorizedContext) throws -> any CredentialSigner {
        SecureEnclaveSigner(key: try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context.laContext))
    }
}

private struct SecureEnclaveSigner: CredentialSigner, @unchecked Sendable {
    let key: SecureEnclave.P256.Signing.PrivateKey

    func sign(_ message: Data) throws -> Data {
        try key.signature(for: message).rawRepresentation
    }
}

/// Kunci perangkat lunak untuk test dan preview. Jangan dipakai di build rilis.
public struct SoftwareKeyFactory: SigningKeyFactory {
    public init() {}

    public func makeKey() throws -> (publicKey: Data, blob: Data) {
        let key = P256.Signing.PrivateKey()
        return (key.publicKey.x963Representation, key.rawRepresentation)
    }

    public func signer(blob: Data, context: AuthorizedContext) throws -> any CredentialSigner {
        SoftwareSigner(key: try P256.Signing.PrivateKey(rawRepresentation: blob))
    }
}

private struct SoftwareSigner: CredentialSigner {
    let key: P256.Signing.PrivateKey

    func sign(_ message: Data) throws -> Data {
        try key.signature(for: message).rawRepresentation
    }
}

/// Menyimpan blob kunci di `SecretStore` dengan `.whenPasscodeSetThisDeviceOnly`,
/// sehingga kunci tidak ikut backup dan hilang bila passcode dimatikan (SDD §5.3).
public struct DeviceKeyStore: CredentialKeyStore {
    private let store: any SecretStore
    private let factory: any SigningKeyFactory

    public init(store: any SecretStore, factory: any SigningKeyFactory) {
        self.store = store
        self.factory = factory
    }

    public static func storageKey(for credentialID: Data) -> String {
        "cred.key.\(credentialID.hexString)"
    }

    public func createKey(for credentialID: Data) throws -> Data {
        let (publicKey, blob) = try factory.makeKey()
        try store.set(blob, for: Self.storageKey(for: credentialID), accessibility: .whenPasscodeSetThisDeviceOnly)
        return publicKey
    }

    public func signer(for credentialID: Data, context: AuthorizedContext) throws -> any CredentialSigner {
        guard let blob = try store.get(Self.storageKey(for: credentialID)) else { throw ANError.keyUnavailable }
        return try factory.signer(blob: blob, context: context)
    }

    public func hasKey(for credentialID: Data) throws -> Bool {
        try store.get(Self.storageKey(for: credentialID)) != nil
    }

    public func deleteKey(for credentialID: Data) throws {
        try store.delete(Self.storageKey(for: credentialID))
    }

    public func moveKey(from: Data, to: Data) throws {
        guard let blob = try store.get(Self.storageKey(for: from)) else { throw ANError.keyUnavailable }
        try store.set(blob, for: Self.storageKey(for: to), accessibility: .whenPasscodeSetThisDeviceOnly)
        try store.delete(Self.storageKey(for: from))
    }
}

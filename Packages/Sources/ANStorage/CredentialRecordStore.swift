import ANCore
import ANCrypto
import CryptoKit
import Foundation

/// Sertifikat dan kunci publik reader group per kredensial (SDD §5.3).
public struct CredentialRecord: Codable, Equatable, Sendable {
    public let credentialID: Data
    public let certificate: Data
    public let notAfter: Date
    /// Hex `group_id` → [x963 aktif, x963 berikutnya]; format sama dengan `ProvisionedCredential`.
    public let groupKeys: [String: [Data]]

    public init(credentialID: Data, certificate: Data, notAfter: Date, groupKeys: [String: [Data]]) {
        self.credentialID = credentialID
        self.certificate = certificate
        self.notAfter = notAfter
        self.groupKeys = groupKeys
    }

    public func material(suspended: Bool) throws -> CredentialMaterial {
        var keys: [Data: [P256.Signing.PublicKey]] = [:]
        let decoy = ANP1Signatures.timingDecoyKey.x963Representation
        for (hexGroup, publicKeys) in groupKeys {
            guard let groupID = Data(hexString: hexGroup), groupID.count == 8,
                  (1...ANP1Signatures.maxKeysPerGroup).contains(publicKeys.count),
                  !publicKeys.contains(decoy)
            else { throw ANError.invalidData }
            keys[groupID] = try publicKeys.map { raw in
                do { return try P256.Signing.PublicKey(x963Representation: raw) } catch { throw ANError.invalidData }
            }
        }
        return CredentialMaterial(credentialID: credentialID, certificate: certificate, notAfter: notAfter, suspended: suspended, groupKeys: keys)
    }
}

public protocol CredentialRecordStore: Sendable {
    func save(_ record: CredentialRecord) throws
    func record(for credentialID: Data) throws -> CredentialRecord?
    func delete(_ credentialID: Data) throws
}

public struct KeychainCredentialRecordStore: CredentialRecordStore {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    private static func key(for credentialID: Data) -> String {
        "cred.record.\(credentialID.hexString)"
    }

    public func save(_ record: CredentialRecord) throws {
        try store.set(JSONEncoder().encode(record), for: Self.key(for: record.credentialID), accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    public func record(for credentialID: Data) throws -> CredentialRecord? {
        try store.get(Self.key(for: credentialID)).map { try JSONDecoder().decode(CredentialRecord.self, from: $0) }
    }

    public func delete(_ credentialID: Data) throws {
        try store.delete(Self.key(for: credentialID))
    }
}

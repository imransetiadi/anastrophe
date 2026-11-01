import CryptoKit
import Foundation

/// Penanda tangan transcript dengan kunci kredensial (Secure Enclave di produksi).
public protocol CredentialSigner: Sendable {
    /// Tanda tangan ECDSA P-256/SHA-256, format raw 64 B.
    func sign(_ message: Data) throws -> Data
}

/// Counter monoton per kredensial (deteksi anomali, SDD §7.6).
public protocol CounterStore: Sendable {
    func next(for credentialID: Data) throws -> UInt32
}

/// Data kredensial yang dibutuhkan satu transaksi ANP/1 (SDD §7.3).
public struct CredentialMaterial: Sendable {
    public let credentialID: Data      // 16 B
    public let certificate: Data       // CredentialCert CBOR, ≤ 200 B
    public let notAfter: Date
    public let suspended: Bool
    /// group_id (8 B) → kunci publik reader group [aktif, berikutnya].
    public let groupKeys: [Data: [P256.Signing.PublicKey]]

    public init(credentialID: Data, certificate: Data, notAfter: Date, suspended: Bool, groupKeys: [Data: [P256.Signing.PublicKey]]) {
        self.credentialID = credentialID
        self.certificate = certificate
        self.notAfter = notAfter
        self.suspended = suspended
        self.groupKeys = groupKeys
    }

    /// `cert_hash` = 8 byte pertama SHA-256 sertifikat.
    public var certificateHash: Data { Data(SHA256.hash(data: certificate).prefix(8)) }
}

/// Verifikasi `sig_R`, dapat diganti di test untuk menghitung panggilan.
public struct ANP1ReaderVerifier: Sendable {
    public let verify: @Sendable (_ signature: Data, _ transcript: Data, _ keys: [P256.Signing.PublicKey]) -> Bool

    public init(verify: @escaping @Sendable (Data, Data, [P256.Signing.PublicKey]) -> Bool) {
        self.verify = verify
    }

    public static let live = ANP1ReaderVerifier { signature, transcript, keys in
        ANP1Signatures.verifyReader(signature: signature, transcript: transcript, groupPublicKeys: keys)
    }
}

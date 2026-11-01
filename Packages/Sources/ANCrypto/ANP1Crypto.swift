import CryptoKit
import Foundation

/// Kunci sesi per transaksi: `(K_pr, K_rp, IV_base)` (SDD §7.6).
public struct ANP1SessionKeys: Sendable {
    public let phoneToReader: SymmetricKey  // K_pr
    public let readerToPhone: SymmetricKey  // K_rp
    public let ivBase: Data

    public init(phoneToReader: SymmetricKey, readerToPhone: SymmetricKey, ivBase: Data) {
        self.phoneToReader = phoneToReader
        self.readerToPhone = readerToPhone
        self.ivBase = ivBase
    }

    /// Nonce AES-GCM = `IV_base XOR seq` (seq per arah, mulai 0, big-endian di byte terakhir).
    public func nonceBytes(seq: UInt64) -> Data {
        var bytes = [UInt8](ivBase)
        for i in 0..<8 {
            bytes[bytes.count - 1 - i] ^= UInt8((seq >> (8 * UInt64(i))) & 0xFF)
        }
        return Data(bytes)
    }

    /// AES-128-GCM dengan AAD = header APDU. Keluaran: ciphertext ‖ tag.
    public func seal(_ plaintext: Data, key: SymmetricKey, seq: UInt64, header: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceBytes(seq: seq)), authenticating: header)
        return box.ciphertext + box.tag
    }

    public func open(_ sealed: Data, key: SymmetricKey, seq: UInt64, header: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceBytes(seq: seq)),
            ciphertext: sealed.dropLast(16),
            tag: sealed.suffix(16)
        )
        return try AES.GCM.open(box, using: key, authenticating: header)
    }
}

extension ANP1SessionKeys: Equatable {
    public static func == (a: Self, b: Self) -> Bool {
        a.ivBase == b.ivBase && a.phoneToReader.bytes == b.phoneToReader.bytes && a.readerToPhone.bytes == b.readerToPhone.bytes
    }
}

private extension SymmetricKey {
    var bytes: Data { withUnsafeBytes { Data($0) } }
}

public enum ANP1KeySchedule {
    /// `Z = ECDH(my_eph, peer_eph)`; `HKDF-SHA256(Z, salt = txn_id, info = "ANP1-KEYS" ‖ group_id, L = 44)`.
    public static func derive(
        myEphemeral: P256.KeyAgreement.PrivateKey,
        peerEphemeral: Data,
        transactionID: Data,
        groupID: Data
    ) throws -> ANP1SessionKeys {
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: peerEphemeral)
        let shared = try myEphemeral.sharedSecretFromKeyAgreement(with: peer)
        let okm = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: transactionID,
            sharedInfo: Data("ANP1-KEYS".utf8) + groupID,
            outputByteCount: 16 + 16 + 12
        ).withUnsafeBytes { Data($0) }
        return ANP1SessionKeys(
            phoneToReader: SymmetricKey(data: okm.prefix(16)),
            readerToPhone: SymmetricKey(data: okm.dropFirst(16).prefix(16)),
            ivBase: Data(okm.suffix(12))
        )
    }
}

public enum ANP1Signatures {
    public static let readerDomain = Data("ANP1-R".utf8)
    public static let phoneDomain = Data("ANP1-P".utf8)
    /// Kunci reader group per gedung: aktif + berikutnya (SDD §7.3). Juga jumlah verifikasi
    /// tetap per percobaan AUTH1 agar timing `6982` setara (TC-PROTO-05).
    public static let maxKeysPerGroup = 2
    /// Kunci publik untuk menyamakan kerja verifikasi. Skalar privatnya publik, jadi hasil
    /// verifikasinya selalu dibuang dan kunci ini tidak boleh diprovisikan.
    public static let timingDecoyKey = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x01, count: 32)).publicKey

    /// Verifikasi `sig_R` terhadap kunci publik reader group (aktif + berikutnya).
    public static func verifyReader(signature: Data, transcript: Data, groupPublicKeys: [P256.Signing.PublicKey]) -> Bool {
        guard let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
        let message = readerDomain + transcript
        return groupPublicKeys.contains { $0.isValidSignature(sig, for: message) }
    }

    /// Pesan yang ditandatangani kunci kredensial: `"ANP1-P" ‖ T ‖ cred_id ‖ counter`.
    public static func phoneMessage(transcript: Data, credentialID: Data, counter: UInt32) -> Data {
        phoneDomain + transcript + credentialID + withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    }
}

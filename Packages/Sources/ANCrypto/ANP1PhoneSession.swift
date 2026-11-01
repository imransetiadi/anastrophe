import ANCore
import ANProtocol
import CryptoKit
import Foundation

/// Sisi kriptografi ponsel untuk satu transaksi ANP/1 (SDD §7.5–7.6).
public final class ANP1PhoneSession: ANP1CredentialProvider {

    private let material: CredentialMaterial
    private let signer: any CredentialSigner
    private let counters: any CounterStore
    private let now: Date
    private let verifier: ANP1ReaderVerifier
    private var injectedEphemeral: P256.KeyAgreement.PrivateKey?
    private var ephemeral: P256.KeyAgreement.PrivateKey?
    private var keys: ANP1SessionKeys?

    /// `ephemeral` hanya diisi untuk test vector; tanpa itu setiap AUTH0 memakai kunci baru.
    public init(
        material: CredentialMaterial,
        signer: any CredentialSigner,
        counters: any CounterStore,
        now: Date = .now,
        ephemeral: P256.KeyAgreement.PrivateKey? = nil,
        verifier: ANP1ReaderVerifier = .live
    ) {
        self.material = material
        self.signer = signer
        self.counters = counters
        self.now = now
        self.injectedEphemeral = ephemeral
        self.verifier = verifier
    }

    public func ephemeralPublicKey() -> Data {
        let key = injectedEphemeral ?? P256.KeyAgreement.PrivateKey()
        injectedEphemeral = nil
        ephemeral = key
        keys = nil
        return key.publicKey.x963Representation
    }

    public func verifyReader(_ handshake: ANP1Handshake, signature: Data) -> Bool {
        let known = material.groupKeys[handshake.groupID] ?? []
        let transcript = handshake.transcript
        // Tanpa short-circuit: setiap kunci diverifikasi, lalu dipadankan dengan decoy
        // sampai jumlah verifikasi sama untuk group dikenal maupun tidak.
        var valid = false
        for key in known where verifier.verify(signature, transcript, [key]) {
            valid = true
        }
        for _ in known.count..<max(known.count, ANP1Signatures.maxKeysPerGroup) {
            _ = verifier.verify(signature, transcript, [ANP1Signatures.timingDecoyKey])
        }
        return valid
    }

    public func sealIdentity(_ handshake: ANP1Handshake, header: Data) throws -> Data {
        guard !material.suspended else { throw ANP1Failure.credentialSuspended }
        guard now <= material.notAfter else { throw ANP1Failure.credentialExpired }
        guard let ephemeral else { throw ANError.internalError }
        let keys = try ANP1KeySchedule.derive(
            myEphemeral: ephemeral,
            peerEphemeral: handshake.readerEphemeral,
            transactionID: handshake.transactionID,
            groupID: handshake.groupID
        )
        let counter = try counters.next(for: material.credentialID)
        let signature = try signer.sign(ANP1Signatures.phoneMessage(
            transcript: handshake.transcript,
            credentialID: material.credentialID,
            counter: counter
        ))
        let plaintext = TLV.encodeAll([
            TLV(tag: ANP1.Tag.credentialID, value: material.credentialID),
            TLV(tag: ANP1.Tag.counter, value: withUnsafeBytes(of: counter.bigEndian) { Data($0) }),
            TLV(tag: ANP1.Tag.certificateHash, value: material.certificateHash),
            TLV(tag: ANP1.Tag.phoneSignature, value: signature),
        ])
        let sealed = try keys.seal(plaintext, key: keys.phoneToReader, seq: 0, header: header)
        self.keys = keys  // GET_CERT/RESULT hanya mungkin setelah identitas berhasil disegel
        return sealed
    }

    public func sealCertificate(header: Data) throws -> Data {
        guard let keys else { throw ANError.internalError }
        return try keys.seal(material.certificate, key: keys.phoneToReader, seq: 1, header: header)
    }

    public func openResult(_ sealed: Data, header: Data) throws -> ANP1Result {
        guard let keys else { throw ANError.internalError }
        let tlv = try TLV.decodeAll(try keys.open(sealed, key: keys.readerToPhone, seq: 0, header: header))
        let status = try tlv.value(for: ANP1.Tag.resultStatus, length: 1)[0]
        let reason = try tlv.value(for: ANP1.Tag.resultReason, length: 1)[0]
        switch status {
        case 0x00: return .granted
        case 0x01: return .denied(reason: reason)
        default: throw StatusWord.wrongData
        }
    }
}

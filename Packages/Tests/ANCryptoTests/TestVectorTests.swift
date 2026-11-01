import ANProtocol
import ANTestSupport
import CryptoKit
import Foundation
import Testing
@testable import ANCrypto

/// `anp1-v1.json` dibuat oleh `scripts/anp1/gen_vectors.py` (pustaka Python
/// `cryptography`), implementasi independen dari kode Swift (TC-PROTO-01).
struct ANP1Vector: Decodable {
    struct Expected: Decodable {
        let transcript, kPr, kRp, ivBase, certHash: String
        let auth1Plaintext, auth1Ciphertext, certCiphertext: String
        let resultPlaintextGranted, resultCiphertextGranted: String
        let apdus: [String: String]
    }

    let groupPriv, groupId, readerEphPriv, phoneEphPriv, credPriv: String
    let txnId, credId, certificate, sigR, sigP: String
    let counter: UInt32
    let expected: Expected

    static func load() throws -> ANP1Vector {
        let url = try #require(Bundle.module.url(forResource: "anp1-v1", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ANP1Vector.self, from: Data(contentsOf: url))
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

private struct FixedCounterStore: CounterStore {
    let value: UInt32
    func next(for credentialID: Data) throws -> UInt32 { value }
}

@Suite("Test vector bersama ANP/1 v1 (TC-PROTO-01)")
struct TestVectorTests {
    let v: ANP1Vector
    let groupKey: P256.Signing.PrivateKey
    let readerEph: P256.KeyAgreement.PrivateKey
    let phoneEph: P256.KeyAgreement.PrivateKey
    let credKey: P256.Signing.PrivateKey

    init() throws {
        v = try ANP1Vector.load()
        groupKey = try P256.Signing.PrivateKey(rawRepresentation: Data(hex: v.groupPriv))
        readerEph = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v.readerEphPriv))
        phoneEph = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v.phoneEphPriv))
        credKey = try P256.Signing.PrivateKey(rawRepresentation: Data(hex: v.credPriv))
    }

    var transcript: Data {
        ANP1.transcript(
            groupID: Data(hex: v.groupId),
            readerEphemeral: readerEph.publicKey.x963Representation,
            phoneEphemeral: phoneEph.publicKey.x963Representation,
            transactionID: Data(hex: v.txnId)
        )
    }

    func phoneKeys() throws -> ANP1SessionKeys {
        try ANP1KeySchedule.derive(myEphemeral: phoneEph, peerEphemeral: readerEph.publicKey.x963Representation, transactionID: Data(hex: v.txnId), groupID: Data(hex: v.groupId))
    }

    @Test func transcriptSamaDenganVector() {
        #expect(transcript == Data(hex: v.expected.transcript))
    }

    @Test func kunciSesiSamaDenganVector() throws {
        let phone = try phoneKeys()
        let reader = try ANP1KeySchedule.derive(myEphemeral: readerEph, peerEphemeral: phoneEph.publicKey.x963Representation, transactionID: Data(hex: v.txnId), groupID: Data(hex: v.groupId))
        let expected = ANP1SessionKeys(
            phoneToReader: SymmetricKey(data: Data(hex: v.expected.kPr)),
            readerToPhone: SymmetricKey(data: Data(hex: v.expected.kRp)),
            ivBase: Data(hex: v.expected.ivBase)
        )
        #expect(phone == expected)
        #expect(reader == expected)
    }

    @Test func ciphertextAuth1SamaDenganVector() throws {
        let keys = try phoneKeys()
        let header = Data([0x80, 0x12, 0x00, 0x00])
        let plaintext = Data(hex: v.expected.auth1Plaintext)
        #expect(try keys.seal(plaintext, key: keys.phoneToReader, seq: 0, header: header) == Data(hex: v.expected.auth1Ciphertext))
        #expect(try keys.open(Data(hex: v.expected.auth1Ciphertext), key: keys.phoneToReader, seq: 0, header: header) == plaintext)
    }

    @Test func ciphertextResultSamaDenganVector() throws {
        let keys = try phoneKeys()
        let header = Data([0x80, 0x16, 0x00, 0x00])
        let plaintext = Data(hex: v.expected.resultPlaintextGranted)
        #expect(try keys.seal(plaintext, key: keys.readerToPhone, seq: 0, header: header) == Data(hex: v.expected.resultCiphertextGranted))
        #expect(try keys.open(Data(hex: v.expected.resultCiphertextGranted), key: keys.readerToPhone, seq: 0, header: header) == plaintext)
    }

    @Test func tandaTanganVectorValid() throws {
        #expect(ANP1Signatures.verifyReader(signature: Data(hex: v.sigR), transcript: transcript, groupPublicKeys: [groupKey.publicKey]))
        let sigP = try P256.Signing.ECDSASignature(rawRepresentation: Data(hex: v.sigP))
        let message = ANP1Signatures.phoneMessage(transcript: transcript, credentialID: Data(hex: v.credId), counter: v.counter)
        #expect(credKey.publicKey.isValidSignature(sigP, for: message))
    }

    @Test func semuaPesanVectorDiBawah255() {
        #expect(v.expected.apdus.count == 8)
        #expect(v.expected.apdus.values.allSatisfy { Data(hex: $0).count < 255 })
    }

    @Test func responderDenganSesiPonselCocokDenganVector() throws {
        let material = CredentialMaterial(
            credentialID: Data(hex: v.credId),
            certificate: Data(hex: v.certificate),
            notAfter: .distantFuture,
            suspended: false,
            groupKeys: [Data(hex: v.groupId): [groupKey.publicKey]]
        )
        let session = ANP1PhoneSession(material: material, signer: SoftwareSigner(key: credKey), counters: FixedCounterStore(value: v.counter), ephemeral: phoneEph)
        var responder = ANP1Responder(credentials: session)
        let apdus = v.expected.apdus.mapValues { Data(hex: $0) }

        #expect(responder.handle(apdus["select_command"]!).suffix(2) == Data([0x90, 0x00]))
        #expect(responder.handle(apdus["auth0_command"]!) == apdus["auth0_response"]!)

        // sig_P CryptoKit teracak, jadi ciphertext AUTH1 dibandingkan per field setelah dibuka.
        let auth1 = responder.handle(apdus["auth1_command"]!)
        #expect(auth1.suffix(2) == Data([0x90, 0x00]))
        let keys = try phoneKeys()
        let tlv = try TLV.decodeAll(try keys.open(auth1.dropLast(2), key: keys.phoneToReader, seq: 0, header: Data([0x80, 0x12, 0x00, 0x00])))
        let expectedTLV = try TLV.decodeAll(Data(hex: v.expected.auth1Plaintext))
        #expect(Array(tlv.prefix(3)) == Array(expectedTLV.prefix(3)))
        let sigP = try P256.Signing.ECDSASignature(rawRepresentation: tlv.value(for: ANP1.Tag.phoneSignature, length: 64))
        #expect(credKey.publicKey.isValidSignature(sigP, for: ANP1Signatures.phoneMessage(transcript: transcript, credentialID: Data(hex: v.credId), counter: v.counter)))

        #expect(responder.handle(apdus["get_cert_command"]!) == apdus["get_cert_response"]!)
        #expect(responder.handle(apdus["result_command"]!) == Data([0x90, 0x00]))
        #expect(responder.outcome == .granted)
    }
}

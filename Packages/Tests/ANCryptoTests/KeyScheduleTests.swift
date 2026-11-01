import CryptoKit
import Foundation
import Testing
@testable import ANCrypto

@Suite("Kriptografi ANP/1 (SDD §7.2, §7.6)")
struct KeyScheduleTests {
    let groupID = Data(repeating: 0xAA, count: 8)
    let txnID = Data(repeating: 0x33, count: 16)

    @Test func ponselDanReaderMenurunkanKunciSama() throws {
        let phone = P256.KeyAgreement.PrivateKey()
        let reader = P256.KeyAgreement.PrivateKey()
        let p = try ANP1KeySchedule.derive(myEphemeral: phone, peerEphemeral: reader.publicKey.x963Representation, transactionID: txnID, groupID: groupID)
        let r = try ANP1KeySchedule.derive(myEphemeral: reader, peerEphemeral: phone.publicKey.x963Representation, transactionID: txnID, groupID: groupID)
        #expect(p == r)
        #expect(p.ivBase.count == 12)
    }

    @Test func nonceAdalahIvXorSeq() {
        let keys = ANP1SessionKeys(phoneToReader: SymmetricKey(size: .bits128), readerToPhone: SymmetricKey(size: .bits128), ivBase: Data(repeating: 0, count: 12))
        #expect(keys.nonceBytes(seq: 0) == Data(repeating: 0, count: 12))
        #expect(keys.nonceBytes(seq: 0x0102) == Data(repeating: 0, count: 10) + Data([0x01, 0x02]))
    }

    @Test func sealOpenDenganAADHeader() throws {
        let keys = ANP1SessionKeys(phoneToReader: SymmetricKey(size: .bits128), readerToPhone: SymmetricKey(size: .bits128), ivBase: Data(repeating: 7, count: 12))
        let header = Data([0x80, 0x12, 0x00, 0x00])
        let sealed = try keys.seal(Data("halo".utf8), key: keys.phoneToReader, seq: 0, header: header)
        #expect(try keys.open(sealed, key: keys.phoneToReader, seq: 0, header: header) == Data("halo".utf8))
        #expect(throws: (any Error).self) { try keys.open(sealed, key: keys.phoneToReader, seq: 0, header: Data([0x80, 0x14, 0, 0])) }
    }

    @Test func verifikasiSigR() throws {
        let readerGroup = P256.Signing.PrivateKey()
        let transcript = Data("T".utf8)
        let signature = try readerGroup.signature(for: Data("ANP1-R".utf8) + transcript).rawRepresentation
        #expect(ANP1Signatures.verifyReader(signature: signature, transcript: transcript, groupPublicKeys: [readerGroup.publicKey]))
        #expect(!ANP1Signatures.verifyReader(signature: signature, transcript: Data("X".utf8), groupPublicKeys: [readerGroup.publicKey]))
        #expect(!ANP1Signatures.verifyReader(signature: signature, transcript: transcript, groupPublicKeys: []))
    }
}

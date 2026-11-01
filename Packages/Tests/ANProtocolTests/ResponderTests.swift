import Foundation
import Testing
@testable import ANProtocol

/// Kredensial palsu: hanya mengenal satu group dan satu tanda tangan reader yang sah.
final class FakeCredentials: ANP1CredentialProvider {
    let knownGroup = Data(repeating: 0xAA, count: 8)
    let validSignature = Data(repeating: 0x5A, count: 64)
    var sealFailure: (any Error)?

    func ephemeralPublicKey() -> Data { Data([0x04]) + Data(repeating: 0x11, count: 64) }

    func verifyReader(_ handshake: ANP1Handshake, signature: Data) -> Bool {
        handshake.groupID == knownGroup && signature == validSignature
    }

    func sealIdentity(_ handshake: ANP1Handshake, header: Data) throws -> Data {
        if let sealFailure { throw sealFailure }
        return Data(repeating: 0xEE, count: 120)
    }
    func sealCertificate(header: Data) throws -> Data { Data(repeating: 0xCC, count: 170) }
    func openResult(_ sealed: Data, header: Data) throws -> ANP1Result { .granted }
}

@Suite("Responder ANP/1 sisi ponsel (SDD §7.4–7.6, ADR-0003)")
struct ResponderTests {
    let creds = FakeCredentials()

    func select() -> Data { Data([0x00, 0xA4, 0x04, 0x00, 0x09]) + ANP1.aid }

    func auth0(group: Data) -> Data {
        let body = TLV.encodeAll([
            TLV(tag: 0xC1, value: group),
            TLV(tag: 0xC2, value: Data([0x04]) + Data(repeating: 0x22, count: 64)),
            TLV(tag: 0xC3, value: Data(repeating: 0x33, count: 16)),
        ])
        return Data([0x80, 0x10, 0x00, 0x00, UInt8(body.count)]) + body
    }

    func auth1(signature: Data) -> Data {
        let body = TLV.encodeAll([TLV(tag: 0xC4, value: signature)])
        return Data([0x80, 0x12, 0x00, 0x00, UInt8(body.count)]) + body
    }

    func run(group: Data, signature: Data) -> Data {
        var responder = ANP1Responder(credentials: creds)
        _ = responder.handle(select())
        _ = responder.handle(auth0(group: group))
        return responder.handle(auth1(signature: signature))
    }

    @Test func transaksiSahMengembalikanIdentitasTerenkripsi() {
        let response = run(group: creds.knownGroup, signature: creds.validSignature)
        #expect(response.suffix(2) == Data([0x90, 0x00]))
        #expect(response.count < 255)
    }

    @Test func groupTakDikenalDanTandaTanganSalahIdentik() {
        let unknownGroup = run(group: Data(repeating: 0xBB, count: 8), signature: creds.validSignature)
        let badSignature = run(group: creds.knownGroup, signature: Data(repeating: 0x00, count: 64))
        #expect(unknownGroup == Data([0x69, 0x82]))
        #expect(badSignature == unknownGroup)
    }

    @Test func auth0SelaluMembalasEphemeralTanpaMembocorkanGroup() {
        var a = ANP1Responder(credentials: creds)
        var b = ANP1Responder(credentials: creds)
        _ = a.handle(select()); _ = b.handle(select())
        let known = a.handle(auth0(group: creds.knownGroup))
        let unknown = b.handle(auth0(group: Data(repeating: 0xBB, count: 8)))
        #expect(known == unknown)
        #expect(known.suffix(2) == Data([0x90, 0x00]))
    }

    @Test func auth1TanpaAuth0Ditolak() {
        var responder = ANP1Responder(credentials: creds)
        _ = responder.handle(select())
        #expect(responder.handle(auth1(signature: creds.validSignature)) == Data([0x69, 0x82]))
    }

    @Test func auth0TanpaSelectTetapDitolak() {
        var responder = ANP1Responder(credentials: creds)
        #expect(responder.handle(auth0(group: creds.knownGroup)) == Data([0x69, 0x82]))
        #expect(responder.handle(auth0(group: creds.knownGroup)) == Data([0x69, 0x82]))
    }

    @Test(arguments: [ANP1Failure.credentialExpired, .credentialSuspended])
    func kegagalanLokalTerlihat(failure: ANP1Failure) {
        // Temuan review I5: coordinator harus tahu kenapa ponsel menjawab 6985.
        creds.sealFailure = failure
        var responder = ANP1Responder(credentials: creds)
        _ = responder.handle(select())
        _ = responder.handle(auth0(group: creds.knownGroup))
        #expect(responder.handle(auth1(signature: creds.validSignature)) == Data([0x69, 0x85]))
        #expect(responder.localFailure == failure)
        _ = responder.handle(select())
        #expect(responder.localFailure == nil)
    }

    @Test func gagalMenyegelTidakMembukaGetCert() {
        // Minor 3: setelah 6F00 (mis. tanda tangan SE gagal) reader tidak boleh melanjutkan transaksi.
        struct SigningFailed: Error {}
        creds.sealFailure = SigningFailed()
        var responder = ANP1Responder(credentials: creds)
        _ = responder.handle(select())
        _ = responder.handle(auth0(group: creds.knownGroup))
        #expect(responder.handle(auth1(signature: creds.validSignature)) == Data([0x6F, 0x00]))
        #expect(responder.handle(Data([0x80, 0x14, 0x00, 0x00])) == Data([0x69, 0x82]))
        #expect(responder.handle(Data([0x80, 0x16, 0x00, 0x00, 0x01, 0x00])) == Data([0x69, 0x82]))
        #expect(responder.outcome == nil)
    }

    @Test func p1p2SelainNolDitolak() {
        // Minor 4: header berbeda = AAD berbeda dengan nonce sama; tolak P1/P2 ≠ 00.
        var responder = ANP1Responder(credentials: creds)
        _ = responder.handle(select())
        _ = responder.handle(auth0(group: creds.knownGroup))
        #expect(responder.handle(auth1(signature: creds.validSignature)).suffix(2) == Data([0x90, 0x00]))
        #expect(responder.handle(Data([0x80, 0x14, 0x01, 0x00])) == Data([0x6A, 0x80]))
        #expect(responder.handle(Data([0x80, 0x14, 0x00, 0x00])).suffix(2) == Data([0x90, 0x00]))
    }

    @Test func insTakDikenal() {
        var responder = ANP1Responder(credentials: creds)
        _ = responder.handle(select())
        #expect(responder.handle(Data([0x80, 0x7E, 0x00, 0x00])) == Data([0x6D, 0x00]))
    }
}

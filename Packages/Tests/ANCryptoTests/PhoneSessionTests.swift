import ANProtocol
import ANTestSupport
import CryptoKit
import Foundation
import Testing
@testable import ANCrypto

/// Kunci, material, dan sesi untuk satu kredensial uji.
struct Fixture {
    let groupKey = P256.Signing.PrivateKey()
    let groupID = Data(repeating: 0xA1, count: 8)
    let credentialKey = P256.Signing.PrivateKey()
    let counters = InMemoryCounterStore()
    let certificate = Data(repeating: 0xCE, count: 150)

    func material(notAfter: Date = .now.addingTimeInterval(7 * 86_400), suspended: Bool = false) -> CredentialMaterial {
        CredentialMaterial(
            credentialID: Data(repeating: 0xC1, count: 16),
            certificate: certificate,
            notAfter: notAfter,
            suspended: suspended,
            groupKeys: [groupID: [groupKey.publicKey, P256.Signing.PrivateKey().publicKey]]
        )
    }

    func responder(material: CredentialMaterial? = nil, verifier: ANP1ReaderVerifier = .live) -> ANP1Responder {
        ANP1Responder(credentials: ANP1PhoneSession(
            material: material ?? self.material(),
            signer: SoftwareSigner(key: credentialKey),
            counters: counters,
            verifier: verifier
        ))
    }

    func reader(groupID: Data? = nil) -> SoftwareReader {
        SoftwareReader(groupKey: groupKey, groupID: groupID ?? self.groupID)
    }
}

/// Verifier yang mencatat panggilan (Review Focus 1).
final class VerifierSpy: @unchecked Sendable {
    /// Total kunci yang diverifikasi (≈ jumlah operasi ECDSA verify).
    private(set) var keysVerified = 0
    var verifier: ANP1ReaderVerifier {
        ANP1ReaderVerifier { signature, transcript, keys in
            self.keysVerified += keys.count
            return ANP1ReaderVerifier.live.verify(signature, transcript, keys)
        }
    }
}

@Suite("Sesi kriptografi ponsel ANP/1 (SDD §7.4–7.6)")
struct PhoneSessionTests {
    let fixture = Fixture()

    @Test func transaksiLengkapGranted() throws {
        var responder = fixture.responder()
        var reader = fixture.reader()
        let outcome = try reader.run(against: &responder, credentialKey: fixture.credentialKey.publicKey, sendGetCert: false, result: .granted)
        #expect(outcome == .granted)
        #expect(responder.outcome == .granted)
    }

    @Test func jalurGetCert() throws {
        var responder = fixture.responder()
        var reader = fixture.reader()
        let outcome = try reader.run(against: &responder, credentialKey: fixture.credentialKey.publicKey, sendGetCert: true, result: .denied(reason: 0x03))
        #expect(outcome == .denied(reason: 0x03))
        #expect(reader.certificate == fixture.certificate)
        #expect(reader.responses.allSatisfy { $0.count < 255 })
    }

    @Test func replayAuth1DariTransaksiLamaDitolak() throws {
        var first = fixture.responder()
        var reader = fixture.reader()
        try reader.select(&first)
        try reader.auth0(&first)
        let oldSignature = try reader.readerSignature()

        var second = fixture.responder()
        try reader.select(&second)
        try reader.auth0(&second)
        #expect(reader.auth1(&second, signature: oldSignature) == Data([0x69, 0x82]))
    }

    @Test func resultDimodifikasiDitolak() throws {
        var responder = fixture.responder()
        var reader = fixture.reader()
        try reader.select(&responder)
        try reader.auth0(&responder)
        let sealedIdentity = reader.auth1(&responder, signature: try reader.readerSignature()).dropLast(2)
        _ = try reader.openIdentity(Data(sealedIdentity), credentialKey: fixture.credentialKey.publicKey)
        var tampered = try reader.sealedResult(.granted)
        tampered[tampered.startIndex] ^= 0x01
        #expect(reader.sendResult(&responder, sealed: tampered) == Data([0x6A, 0x80]))
        #expect(responder.outcome == nil)
    }

    @Test func sertifikatKedaluwarsa6985SetelahSigRValid() throws {
        let expired = fixture.material(notAfter: .now.addingTimeInterval(-60))
        var responder = fixture.responder(material: expired)
        var reader = fixture.reader()
        try reader.select(&responder)
        try reader.auth0(&responder)
        #expect(reader.auth1(&responder, signature: try reader.readerSignature()) == Data([0x69, 0x85]))

        var other = fixture.responder(material: expired)
        try reader.select(&other)
        try reader.auth0(&other)
        #expect(reader.auth1(&other, signature: Data(repeating: 0x01, count: 64)) == Data([0x69, 0x82]))
    }

    @Test func groupTakDikenalSamaBeratDenganTandaTanganSalah() throws {
        // Review Focus 1: jumlah verifikasi ECDSA harus sama di kedua jalur `6982`.
        let unknownSpy = VerifierSpy()
        var unknown = fixture.responder(verifier: unknownSpy.verifier)
        var reader = fixture.reader(groupID: Data(repeating: 0xBB, count: 8))
        try reader.select(&unknown)
        try reader.auth0(&unknown)
        #expect(reader.auth1(&unknown, signature: try reader.readerSignature()) == Data([0x69, 0x82]))

        let badSignatureSpy = VerifierSpy()
        var known = fixture.responder(verifier: badSignatureSpy.verifier)
        var knownReader = fixture.reader()
        try knownReader.select(&known)
        try knownReader.auth0(&known)
        #expect(knownReader.auth1(&known, signature: Data(repeating: 0x01, count: 64)) == Data([0x69, 0x82]))

        #expect(unknownSpy.keysVerified > 0)
        #expect(unknownSpy.keysVerified == badSignatureSpy.keysVerified)
    }

    @Test func kunciDecoyTidakPernahDiterima() throws {
        // Tanda tangan dengan kunci decoy (skalar publik) tidak boleh lolos untuk group mana pun.
        let decoy = try P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x01, count: 32))
        var responder = fixture.responder()
        var reader = SoftwareReader(groupKey: decoy, groupID: fixture.groupID)
        try reader.select(&responder)
        try reader.auth0(&responder)
        #expect(reader.auth1(&responder, signature: try reader.readerSignature()) == Data([0x69, 0x82]))
    }

    @Test func counterDiambilSekaliPerAuth1() throws {
        var responder = fixture.responder()
        var reader = fixture.reader()
        try reader.select(&responder)
        try reader.auth0(&responder)
        let sealed = reader.auth1(&responder, signature: try reader.readerSignature()).dropLast(2)
        let identity = try reader.openIdentity(Data(sealed), credentialKey: fixture.credentialKey.publicKey)
        #expect(fixture.counters.calls == 1)
        #expect(identity.counter == 1)
    }

    @Test func fuzzApduTidakCrash() {
        var rng = SplitMix64(seed: 0xA11CE)
        let validStatus: Set<Data> = [0x9000, 0x6982, 0x6985, 0x6700, 0x6A80, 0x6D00, 0x6F00].map { Data([UInt8($0 >> 8), UInt8($0 & 0xFF)]) }.reduce(into: []) { $0.insert($1) }
        var responder = fixture.responder()
        for i in 0..<10_000 {
            if i % 50 == 0 { _ = responder.handle(Data([0x00, 0xA4, 0x04, 0x00, 0x09]) + ANP1.aid) }
            var input = Data((0..<Int.random(in: 0...300, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
            if input.count >= 2, Bool.random(using: &rng) {
                input[0] = 0x80
                input[1] = [0x10, 0x12, 0x14, 0x16].randomElement(using: &rng)!
            }
            let response = responder.handle(input)
            #expect(response.count >= 2 && response.count < 255)
            #expect(validStatus.contains(response.suffix(2)))
        }
    }
}

/// PRNG deterministik agar fuzzing dapat diulang.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

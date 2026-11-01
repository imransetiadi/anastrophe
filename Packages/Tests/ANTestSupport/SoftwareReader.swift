import ANCrypto
import ANProtocol
import CryptoKit
import Foundation

/// Sisi reader ANP/1 dalam perangkat lunak (SDD §7.5), untuk menguji ponsel tanpa
/// perangkat keras. Bukan implementasi reader produksi.
public struct SoftwareReader {
    public enum Failure: Error, Equatable {
        case status(Data)
        case badPhoneSignature
        case certificateHashMismatch
    }

    public struct Identity: Equatable {
        public let credentialID: Data
        public let counter: UInt32
        public let certificateHash: Data
    }

    public static let auth1Header = Data([0x80, 0x12, 0x00, 0x00])
    public static let getCertHeader = Data([0x80, 0x14, 0x00, 0x00])
    public static let resultHeader = Data([0x80, 0x16, 0x00, 0x00])

    public let groupKey: P256.Signing.PrivateKey
    public let groupID: Data
    /// Semua respons ponsel yang diterima (body ‖ SW), untuk memeriksa batas ukuran.
    public private(set) var responses: [Data] = []
    public private(set) var transcript = Data()
    public private(set) var certificate: Data?

    private var readerEphemeral = P256.KeyAgreement.PrivateKey()
    private var transactionID = Data()
    private var keys: ANP1SessionKeys?

    public init(groupKey: P256.Signing.PrivateKey, groupID: Data) {
        self.groupKey = groupKey
        self.groupID = groupID
    }

    // MARK: Transaksi lengkap

    /// SELECT → AUTH0 → AUTH1 → (GET_CERT) → RESULT langsung terhadap responder.
    /// Mengembalikan `outcome` ponsel.
    public mutating func run(
        against responder: inout ANP1Responder,
        credentialKey: P256.Signing.PublicKey,
        sendGetCert: Bool,
        result: ANP1Result
    ) throws -> ANP1Result? {
        try select(&responder)
        try auth0(&responder)
        let identity = try openIdentity(try Self.expectOK(auth1(&responder, signature: readerSignature())), credentialKey: credentialKey)
        if sendGetCert {
            try verifyCertificate(try getCertificate(&responder), against: identity)
        }
        _ = try Self.expectOK(sendResult(&responder, sealed: sealedResult(result)))
        return responder.outcome
    }

    /// Transaksi yang sama lewat transport asinkron (mis. sesi emulasi palsu atau link BLE).
    public mutating func run(
        transport: (Data) async throws -> Data,
        credentialKey: P256.Signing.PublicKey,
        sendGetCert: Bool,
        result: ANP1Result
    ) async throws {
        _ = try Self.expectOK(record(try await transport(selectCommand())))
        try acceptAuth0(try Self.expectOK(record(try await transport(auth0Command()))))
        let sealed = try Self.expectOK(record(try await transport(auth1Command(signature: readerSignature()))))
        let identity = try openIdentity(sealed, credentialKey: credentialKey)
        if sendGetCert {
            let cert = try acceptCertificate(try Self.expectOK(record(try await transport(Self.getCertHeader))))
            try verifyCertificate(cert, against: identity)
        }
        _ = try Self.expectOK(record(try await transport(resultCommand(sealed: sealedResult(result)))))
    }

    // MARK: Langkah terhadap responder

    public mutating func select(_ responder: inout ANP1Responder) throws {
        _ = try Self.expectOK(send(&responder, selectCommand()))
    }

    public mutating func auth0(_ responder: inout ANP1Responder) throws {
        try acceptAuth0(try Self.expectOK(send(&responder, auth0Command())))
    }

    /// Respons mentah AUTH1 (body ‖ SW).
    public mutating func auth1(_ responder: inout ANP1Responder, signature: Data) -> Data {
        send(&responder, auth1Command(signature: signature))
    }

    public mutating func getCertificate(_ responder: inout ANP1Responder) throws -> Data {
        try acceptCertificate(try Self.expectOK(send(&responder, Self.getCertHeader)))
    }

    /// Respons mentah RESULT (body ‖ SW).
    public mutating func sendResult(_ responder: inout ANP1Responder, sealed: Data) -> Data {
        send(&responder, resultCommand(sealed: sealed))
    }

    // MARK: Pembentuk perintah & pembaca respons

    public func selectCommand() -> Data {
        Data([0x00, 0xA4, 0x04, 0x00, UInt8(ANP1.aid.count)]) + ANP1.aid
    }

    public mutating func auth0Command() -> Data {
        readerEphemeral = P256.KeyAgreement.PrivateKey()
        transactionID = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let body = TLV.encodeAll([
            TLV(tag: ANP1.Tag.groupID, value: groupID),
            TLV(tag: ANP1.Tag.readerEphemeral, value: readerEphemeral.publicKey.x963Representation),
            TLV(tag: ANP1.Tag.transactionID, value: transactionID),
        ])
        return Data([0x80, 0x10, 0x00, 0x00, UInt8(body.count)]) + body
    }

    public mutating func acceptAuth0(_ body: Data) throws {
        let phoneEphemeral = try TLV.decodeAll(body).value(for: ANP1.Tag.phoneEphemeral, length: 65)
        transcript = ANP1.transcript(groupID: groupID, readerEphemeral: readerEphemeral.publicKey.x963Representation, phoneEphemeral: phoneEphemeral, transactionID: transactionID)
        keys = try ANP1KeySchedule.derive(myEphemeral: readerEphemeral, peerEphemeral: phoneEphemeral, transactionID: transactionID, groupID: groupID)
    }

    /// `sig_R` atas transcript transaksi berjalan.
    public func readerSignature() throws -> Data {
        try groupKey.signature(for: ANP1Signatures.readerDomain + transcript).rawRepresentation
    }

    public func auth1Command(signature: Data) -> Data {
        let body = TLV(tag: ANP1.Tag.readerSignature, value: signature).encoded()
        return Self.auth1Header + Data([UInt8(body.count)]) + body
    }

    public func openIdentity(_ sealed: Data, credentialKey: P256.Signing.PublicKey) throws -> Identity {
        let plaintext = try keys!.open(sealed, key: keys!.phoneToReader, seq: 0, header: Self.auth1Header)
        let tlv = try TLV.decodeAll(plaintext)
        let credentialID = try tlv.value(for: ANP1.Tag.credentialID, length: 16)
        let counter = try tlv.value(for: ANP1.Tag.counter, length: 4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: tlv.value(for: ANP1.Tag.phoneSignature, length: 64))
        let message = ANP1Signatures.phoneMessage(transcript: transcript, credentialID: credentialID, counter: counter)
        guard credentialKey.isValidSignature(signature, for: message) else { throw Failure.badPhoneSignature }
        return Identity(credentialID: credentialID, counter: counter, certificateHash: try tlv.value(for: ANP1.Tag.certificateHash, length: 8))
    }

    public mutating func acceptCertificate(_ sealed: Data) throws -> Data {
        let cert = try keys!.open(sealed, key: keys!.phoneToReader, seq: 1, header: Self.getCertHeader)
        certificate = cert
        return cert
    }

    public func sealedResult(_ result: ANP1Result) throws -> Data {
        let (status, reason): (UInt8, UInt8) = switch result {
        case .granted: (0x00, 0x00)
        case .denied(let reason): (0x01, reason)
        }
        let plaintext = TLV.encodeAll([TLV(tag: ANP1.Tag.resultStatus, value: Data([status])), TLV(tag: ANP1.Tag.resultReason, value: Data([reason]))])
        return try keys!.seal(plaintext, key: keys!.readerToPhone, seq: 0, header: Self.resultHeader)
    }

    public func resultCommand(sealed: Data) -> Data {
        Self.resultHeader + Data([UInt8(sealed.count)]) + sealed
    }

    // MARK: Internal

    private func verifyCertificate(_ cert: Data, against identity: Identity) throws {
        guard Data(SHA256.hash(data: cert).prefix(8)) == identity.certificateHash else { throw Failure.certificateHashMismatch }
    }

    private mutating func send(_ responder: inout ANP1Responder, _ apdu: Data) -> Data {
        record(responder.handle(apdu))
    }

    private mutating func record(_ response: Data) -> Data {
        responses.append(response)
        return response
    }

    private static func expectOK(_ response: Data) throws -> Data {
        guard response.suffix(2) == StatusWord.ok.bytes else { throw Failure.status(response.suffix(2)) }
        return response.dropLast(2)
    }
}

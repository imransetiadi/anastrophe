import Foundation

/// Operasi kriptografi sisi ponsel untuk satu transaksi. Implementasi live:
/// `ANP1PhoneSession` (ANCrypto). Sengaja tidak `Sendable`: satu instance per
/// transaksi, dimiliki satu actor kanal.
public protocol ANP1CredentialProvider: AnyObject {
    /// Kunci publik ephemeral P-256 tak terkompresi (65 B), baru per AUTH0.
    func ephemeralPublicKey() -> Data
    /// `false` bila ponsel tidak punya kunci group ini **atau** tanda tangan salah.
    func verifyReader(_ handshake: ANP1Handshake, signature: Data) -> Bool
    /// Respons AUTH1 terenkripsi K_pr (seq 0): {cred_id, counter, cert_hash, sig_P} + tag.
    func sealIdentity(_ handshake: ANP1Handshake, header: Data) throws -> Data
    /// Respons GET_CERT terenkripsi K_pr (seq 1).
    func sealCertificate(header: Data) throws -> Data
    /// Membuka RESULT terenkripsi K_rp (seq 0).
    func openResult(_ sealed: Data, header: Data) throws -> ANP1Result
}

/// Kegagalan kredensial lokal setelah reader terautentikasi; di jalur radio keduanya `6985`.
public enum ANP1Failure: Error, Equatable, Sendable {
    case credentialExpired
    case credentialSuspended
}

/// State machine ANP/1 sisi ponsel (SDD §7.4–7.6).
///
/// Invarian privasi (ADR-0003): tidak ada identitas yang keluar sebelum `sig_R`
/// valid. AUTH0 selalu dibalas ephemeral key, baik group dikenal maupun tidak,
/// dan AUTH1 membalas `6982` yang identik untuk group tak dikenal maupun
/// tanda tangan salah.
public struct ANP1Responder {
    private enum State {
        case idle
        case selected
        case awaitingAuth1(ANP1Handshake)
        case authenticated
    }

    private let credentials: any ANP1CredentialProvider
    private var state: State = .idle
    /// Keputusan reader setelah RESULT berhasil dibuka; `nil` selama transaksi belum selesai.
    public private(set) var outcome: ANP1Result?
    /// Alasan ponsel menjawab `6985`, agar coordinator bisa mengakhiri sesi dengan jelas.
    public private(set) var localFailure: ANP1Failure?

    public init(credentials: any ANP1CredentialProvider) {
        self.credentials = credentials
    }

    public mutating func handle(_ raw: Data) -> Data {
        do {
            let apdu = try CommandAPDU(raw)
            let body = try dispatch(apdu)
            guard body.count + 2 <= ANP1.maxAPDUSize else { throw StatusWord.internalError }
            return body + StatusWord.ok.bytes
        } catch let sw as StatusWord {
            if sw == .readerNotAuthenticated { resetAfterAuthFailure() }
            return sw.bytes
        } catch let failure as ANP1Failure {
            localFailure = failure
            return StatusWord.credentialSuspended.bytes
        } catch {
            return StatusWord.internalError.bytes
        }
    }

    /// Kembali ke `.selected` agar reader bisa mengulang AUTH0, tetapi jangan
    /// pernah melompati SELECT.
    private mutating func resetAfterAuthFailure() {
        if case .idle = state { return }
        state = .selected
    }

    private mutating func dispatch(_ apdu: CommandAPDU) throws -> Data {
        // Header masuk AAD; P1/P2 lain akan memakai nonce yang sama dengan AAD berbeda.
        if apdu.cla == 0x80, apdu.p1 != 0 || apdu.p2 != 0 { throw StatusWord.wrongData }
        switch (apdu.cla, ANP1.Instruction(rawValue: apdu.ins)) {
        case (0x00, .select):
            guard apdu.p1 == 0x04, apdu.data == ANP1.aid else { throw StatusWord.wrongData }
            state = .selected
            outcome = nil
            localFailure = nil
            return ANP1.fci(versions: [ANP1.version], capabilities: 0x01)

        case (0x80, .auth0):
            guard case .selected = state else { throw StatusWord.readerNotAuthenticated }
            let tlv = try TLV.decodeAll(apdu.data)
            let handshake = ANP1Handshake(
                groupID: try tlv.value(for: ANP1.Tag.groupID, length: 8),
                readerEphemeral: try tlv.value(for: ANP1.Tag.readerEphemeral, length: 65),
                phoneEphemeral: credentials.ephemeralPublicKey(),
                transactionID: try tlv.value(for: ANP1.Tag.transactionID, length: 16)
            )
            state = .awaitingAuth1(handshake)
            return TLV(tag: ANP1.Tag.phoneEphemeral, value: handshake.phoneEphemeral).encoded()

        case (0x80, .auth1):
            guard case let .awaitingAuth1(handshake) = state else { throw StatusWord.readerNotAuthenticated }
            let signature = try TLV.decodeAll(apdu.data).value(for: ANP1.Tag.readerSignature, length: 64)
            guard credentials.verifyReader(handshake, signature: signature) else {
                throw StatusWord.readerNotAuthenticated
            }
            // Status terautentikasi hanya setelah identitas berhasil disegel; kegagalan apa pun
            // (6985/6F00) mengembalikan transaksi ke awal.
            do {
                let sealed = try credentials.sealIdentity(handshake, header: apdu.header)
                state = .authenticated
                return sealed
            } catch {
                state = .selected
                throw error
            }

        case (0x80, .getCert):
            guard case .authenticated = state else { throw StatusWord.readerNotAuthenticated }
            return try credentials.sealCertificate(header: apdu.header)

        case (0x80, .result):
            guard case .authenticated = state else { throw StatusWord.readerNotAuthenticated }
            do {
                outcome = try credentials.openResult(apdu.data, header: apdu.header)
            } catch {
                throw StatusWord.wrongData  // tag GCM salah atau plaintext rusak
            }
            state = .idle
            return Data()

        default:
            throw StatusWord.insNotSupported
        }
    }
}

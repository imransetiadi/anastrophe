import Foundation

/// Konstanta ANP/1 (ADR-0003, SDD §7). Bukan AID Aliro (I-10).
public enum ANP1 {
    public static let aid = Data([0xF0, 0x41, 0x4E, 0x41, 0x53, 0x54, 0x52, 0x4F, 0x01])
    public static let version: UInt8 = 1
    /// Setiap APDU (perintah maupun respons) < 255 B, tanpa extended length (U08).
    public static let maxAPDUSize = 254

    public enum Instruction: UInt8, Sendable {
        case select = 0xA4
        case auth0 = 0x10
        case auth1 = 0x12
        case getCert = 0x14
        case result = 0x16
    }

    public enum Tag {
        public static let groupID: UInt8 = 0xC1
        public static let readerEphemeral: UInt8 = 0xC2
        public static let transactionID: UInt8 = 0xC3
        public static let readerSignature: UInt8 = 0xC4
        public static let phoneEphemeral: UInt8 = 0xD1
        // Plaintext AUTH1 (terenkripsi K_pr)
        public static let credentialID: UInt8 = 0xE1
        public static let counter: UInt8 = 0xE2
        public static let certificateHash: UInt8 = 0xE3
        public static let phoneSignature: UInt8 = 0xE4
        // Plaintext RESULT (terenkripsi K_rp)
        public static let resultStatus: UInt8 = 0xF1
        public static let resultReason: UInt8 = 0xF2
    }

    /// FCI `6F{84 AID, A5{80 versi, 81 kapabilitas}}`. Tidak memuat data identitas.
    public static func fci(versions: [UInt8], capabilities: UInt8) -> Data {
        let proprietary = TLV.encodeAll([
            TLV(tag: 0x80, value: Data(versions)),
            TLV(tag: 0x81, value: Data([capabilities])),
        ])
        let body = TLV.encodeAll([TLV(tag: 0x84, value: aid), TLV(tag: 0xA5, value: proprietary)])
        return TLV(tag: 0x6F, value: body).encoded()
    }

    /// `T = "ANP1" ‖ version ‖ group_id ‖ r_eph_pub ‖ p_eph_pub ‖ txn_id` (SDD §7.6).
    public static func transcript(groupID: Data, readerEphemeral: Data, phoneEphemeral: Data, transactionID: Data) -> Data {
        Data("ANP1".utf8) + Data([version]) + groupID + readerEphemeral + phoneEphemeral + transactionID
    }
}

/// Parameter satu transaksi setelah AUTH0.
public struct ANP1Handshake: Equatable, Sendable {
    public let groupID: Data          // 8 B
    public let readerEphemeral: Data  // 65 B
    public let phoneEphemeral: Data   // 65 B
    public let transactionID: Data    // 16 B

    public init(groupID: Data, readerEphemeral: Data, phoneEphemeral: Data, transactionID: Data) {
        self.groupID = groupID
        self.readerEphemeral = readerEphemeral
        self.phoneEphemeral = phoneEphemeral
        self.transactionID = transactionID
    }

    public var transcript: Data {
        ANP1.transcript(groupID: groupID, readerEphemeral: readerEphemeral, phoneEphemeral: phoneEphemeral, transactionID: transactionID)
    }
}

/// Keputusan reader yang dikirim lewat RESULT.
public enum ANP1Result: Equatable, Sendable {
    case granted
    case denied(reason: UInt8)
}

/// Status word ANP/1 (SDD §7.4).
public enum StatusWord: UInt16, Error, Sendable {
    case ok = 0x9000
    case readerNotAuthenticated = 0x6982
    case credentialSuspended = 0x6985
    case wrongLength = 0x6700
    case wrongData = 0x6A80
    case insNotSupported = 0x6D00
    case internalError = 0x6F00

    public var bytes: Data { Data([UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)]) }
}

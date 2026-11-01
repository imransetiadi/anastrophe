import Foundation

/// Frame BLE: `type(1) ‖ seq(1) ‖ flags(1: bit0 = last) ‖ len(2) ‖ payload` (SDD §7.9).
public struct BLEFrame: Equatable, Sendable {
    public enum MessageType: UInt8, Sendable {
        case hello = 0x01  // pengganti SELECT/FCI
        case auth0 = 0x10
        case auth1 = 0x12
        case getCert = 0x14
        case result = 0x16
        case status = 0x7F
    }

    public static let headerSize = 5

    public let type: MessageType
    public let seq: UInt8
    public let isLast: Bool
    public let payload: Data

    public init(type: MessageType, seq: UInt8, isLast: Bool, payload: Data) {
        self.type = type; self.seq = seq; self.isLast = isLast; self.payload = payload
    }

    public init(decoding data: Data) throws(StatusWord) {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerSize, let type = MessageType(rawValue: bytes[0]) else { throw .wrongData }
        let length = Int(bytes[3]) << 8 | Int(bytes[4])
        guard bytes.count == Self.headerSize + length else { throw .wrongLength }
        self.init(type: type, seq: bytes[1], isLast: bytes[2] & 0x01 == 1, payload: Data(bytes[Self.headerSize...]))
    }

    public func encoded() -> Data {
        Data([type.rawValue, seq, isLast ? 0x01 : 0x00, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]) + payload
    }

    /// Pecah payload sesuai MTU ATT yang dinegosiasikan.
    public static func fragment(type: MessageType, payload: Data, mtu: Int) -> [BLEFrame] {
        let chunk = max(1, mtu - headerSize)
        let bytes = [UInt8](payload)
        var frames: [BLEFrame] = []
        var offset = 0
        var seq: UInt8 = 0
        repeat {
            let end = min(offset + chunk, bytes.count)
            frames.append(BLEFrame(type: type, seq: seq, isLast: end == bytes.count, payload: Data(bytes[offset..<end])))
            offset = end
            seq &+= 1
        } while offset < bytes.count
        return frames
    }
}

/// Merakit fragmen menjadi satu pesan; `seq` harus berurutan dan total dibatasi.
public struct BLEFrameAssembler: Sendable {
    /// Lebih besar dari APDU ANP/1 terbesar (254 B) agar reader yang salah tidak menumpuk memori.
    public static let maxMessageSize = 256

    private var buffer = Data()
    private var expectedSeq: UInt8 = 0
    private var type: BLEFrame.MessageType?

    public init() {}

    public mutating func append(_ frame: BLEFrame) throws(StatusWord) -> (BLEFrame.MessageType, Data)? {
        guard frame.seq == expectedSeq, type == nil || type == frame.type else {
            self = BLEFrameAssembler()
            throw .wrongData
        }
        guard buffer.count + frame.payload.count <= Self.maxMessageSize else {
            self = BLEFrameAssembler()
            throw .wrongLength
        }
        type = frame.type
        buffer.append(frame.payload)
        expectedSeq &+= 1
        guard frame.isLast else { return nil }
        let message = (frame.type, buffer)
        self = BLEFrameAssembler()
        return message
    }
}

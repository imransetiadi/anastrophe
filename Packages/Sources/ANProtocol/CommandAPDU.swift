import Foundation

/// APDU perintah ISO 7816-4 short (Lc ≤ 249 agar total < 255 B).
public struct CommandAPDU: Equatable, Sendable {
    public let cla: UInt8
    public let ins: UInt8
    public let p1: UInt8
    public let p2: UInt8
    public let data: Data

    public init(cla: UInt8, ins: UInt8, p1: UInt8 = 0, p2: UInt8 = 0, data: Data = Data()) throws(StatusWord) {
        guard 5 + data.count <= ANP1.maxAPDUSize else { throw .wrongLength }
        self.cla = cla; self.ins = ins; self.p1 = p1; self.p2 = p2; self.data = data
    }

    public init(_ raw: Data) throws(StatusWord) {
        let bytes = [UInt8](raw)
        guard bytes.count >= 4, bytes.count <= ANP1.maxAPDUSize else { throw .wrongLength }
        var data = Data()
        if bytes.count > 5 {
            let lc = Int(bytes[4])
            guard bytes.count >= 5 + lc else { throw .wrongLength }
            data = Data(bytes[5..<(5 + lc)])
        }
        try self.init(cla: bytes[0], ins: bytes[1], p1: bytes[2], p2: bytes[3], data: data)
    }

    public var header: Data { Data([cla, ins, p1, p2]) }

    public func encoded() -> Data {
        data.isEmpty ? header : header + Data([UInt8(data.count)]) + data
    }
}

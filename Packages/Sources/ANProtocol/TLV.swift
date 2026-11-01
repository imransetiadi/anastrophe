import Foundation

/// TLV satu byte tag, panjang short-form (< 128) atau `81 xx`.
public struct TLV: Equatable, Sendable {
    public let tag: UInt8
    public let value: Data

    public init(tag: UInt8, value: Data) {
        self.tag = tag
        self.value = value
    }

    public func encoded() -> Data {
        let length: Data = value.count < 0x80 ? Data([UInt8(value.count)]) : Data([0x81, UInt8(value.count)])
        return Data([tag]) + length + value
    }

    public static func encodeAll(_ items: [TLV]) -> Data {
        items.reduce(into: Data()) { $0.append($1.encoded()) }
    }

    public static func decodeAll(_ data: Data) throws(StatusWord) -> [TLV] {
        let bytes = [UInt8](data)
        var items: [TLV] = []
        var i = 0
        while i < bytes.count {
            guard i + 1 < bytes.count else { throw .wrongData }
            let tag = bytes[i]
            var length = Int(bytes[i + 1])
            i += 2
            if length == 0x81 {
                guard i < bytes.count else { throw .wrongData }
                length = Int(bytes[i])
                i += 1
            } else if length > 0x81 {
                throw .wrongData
            }
            guard i + length <= bytes.count else { throw .wrongData }
            items.append(TLV(tag: tag, value: Data(bytes[i..<(i + length)])))
            i += length
        }
        return items
    }
}

extension Array where Element == TLV {
    /// Nilai tag dengan panjang tepat; selain itu `6A80`.
    public func value(for tag: UInt8, length: Int) throws(StatusWord) -> Data {
        guard let value = first(where: { $0.tag == tag })?.value, value.count == length else { throw .wrongData }
        return value
    }
}

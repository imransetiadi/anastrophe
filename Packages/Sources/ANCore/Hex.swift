import Foundation

extension Data {
    /// Hex huruf kecil, mis. `000fa1ff`.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// `nil` bila panjang ganjil atau ada karakter non-hex.
    public init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

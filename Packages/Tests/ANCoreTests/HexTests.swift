import Foundation
import Testing
@testable import ANCore

@Suite("Hex")
struct HexTests {
    @Test func roundTrip() {
        let data = Data([0x00, 0x0F, 0xA1, 0xFF])
        #expect(data.hexString == "000fa1ff")
        #expect(Data(hexString: "000FA1ff") == data)
    }

    @Test(arguments: ["0", "zz", "abc"])
    func hexTidakValid(input: String) {
        #expect(Data(hexString: input) == nil)
    }
}

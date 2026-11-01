import Foundation
import Testing
@testable import ANProtocol

@Suite("Framing BLE (SDD §7.9)")
struct BLEFrameTests {
    @Test func headerLimaByte() {
        let frame = BLEFrame(type: .auth0, seq: 3, isLast: true, payload: Data([1, 2, 3]))
        #expect(frame.encoded() == Data([BLEFrame.MessageType.auth0.rawValue, 3, 0x01, 0x00, 0x03, 1, 2, 3]))
    }

    @Test func pesanMelebihiBatasDitolak() throws {
        // Minor 12: buffer perakitan dibatasi; APDU ANP/1 maks 254 B.
        var assembler = BLEFrameAssembler()
        for seq in 0..<3 {
            let frame = BLEFrame(type: .auth1, seq: UInt8(seq), isLast: false, payload: Data(repeating: 0, count: 100))
            if seq < 2 {
                _ = try assembler.append(frame)
            } else {
                #expect(throws: StatusWord.wrongLength) { try assembler.append(frame) }
            }
        }
    }

    @Test(arguments: [23, 64, 185, 512])
    func fragmentasiDanRakitUlang(mtu: Int) throws {
        let payload = Data((0..<180).map { UInt8($0 & 0xFF) })
        let frames = BLEFrame.fragment(type: .getCert, payload: payload, mtu: mtu)
        #expect(frames.allSatisfy { $0.encoded().count <= mtu })
        #expect(frames.last?.isLast == true)
        var assembler = BLEFrameAssembler()
        var result: (BLEFrame.MessageType, Data)?
        for frame in frames { result = try assembler.append(BLEFrame(decoding: frame.encoded())) }
        #expect(result?.0 == .getCert)
        #expect(result?.1 == payload)
    }
}

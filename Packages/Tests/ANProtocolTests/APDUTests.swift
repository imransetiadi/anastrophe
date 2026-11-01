import Foundation
import Testing
@testable import ANProtocol

@Suite("APDU & TLV ANP/1 (SDD §7.4)")
struct APDUTests {
    @Test func aidBukanAliro() {
        #expect(ANP1.aid == Data([0xF0, 0x41, 0x4E, 0x41, 0x53, 0x54, 0x52, 0x4F, 0x01]))
    }

    @Test func parseSelect() throws {
        let raw = Data([0x00, 0xA4, 0x04, 0x00, 0x09]) + ANP1.aid
        let apdu = try CommandAPDU(raw)
        #expect(apdu.cla == 0x00 && apdu.ins == 0xA4 && apdu.p1 == 0x04 && apdu.p2 == 0x00)
        #expect(apdu.data == ANP1.aid)
    }

    @Test func tolakApduTerlaluPanjang() {
        let big = Data(repeating: 0, count: 255)
        #expect(throws: StatusWord.wrongLength) { try CommandAPDU(cla: 0x80, ins: 0x10, data: big) }
    }

    @Test func tlvRoundTrip() throws {
        let items = [TLV(tag: 0xC1, value: Data(repeating: 1, count: 8)), TLV(tag: 0xC3, value: Data(repeating: 2, count: 16))]
        let decoded = try TLV.decodeAll(TLV.encodeAll(items))
        #expect(decoded == items)
    }

    @Test func tlvTerpotongDitolak() {
        #expect(throws: StatusWord.wrongData) { try TLV.decodeAll(Data([0xC1, 0x08, 0x00])) }
    }

    @Test func fciTanpaIdentitas() {
        // FCI 6F{84 AID, A5{80 versi, 81 kapabilitas}}; tidak ada tag identitas E1/E3.
        let fci = ANP1.fci(versions: [1], capabilities: 0x01)
        #expect(fci.first == 0x6F)
        #expect(fci.count < 64)
        #expect(!fci.contains(0xE1))
    }
}

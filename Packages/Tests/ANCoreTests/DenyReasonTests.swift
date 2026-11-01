import Testing
@testable import ANCore

@Suite("Kode alasan RESULT ANP/1 (SDD §7.4)")
struct DenyReasonTests {
    @Test(arguments: [
        (UInt8(0x01), DenyReason.expired), (0x02, .suspended), (0x03, .revoked),
        (0x04, .outsideSchedule), (0x05, .zoneNotAllowed), (0x00, .unknown), (0xFF, .unknown),
    ])
    func kodeAlasan(code: UInt8, reason: DenyReason) {
        #expect(DenyReason(anp1Code: code) == reason)
    }
}

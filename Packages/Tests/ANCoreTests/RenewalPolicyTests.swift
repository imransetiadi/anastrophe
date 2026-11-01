import Foundation
import Testing
@testable import ANCore

@Suite("Kebutuhan perpanjangan sertifikat (FR-45, ADR-0023)")
struct RenewalPolicyTests {
    static let start = Date(timeIntervalSince1970: 1_794_000_000)
    static let end = start.addingTimeInterval(7 * 86_400)

    @Test(arguments: [
        (0.0, RenewalNeed.none),
        (3.4, .none),
        (3.5, .soon),  // tepat separuh masa berlaku
        (6.9, .soon),
        (7.0, .expired),
        (9.0, .expired),
    ])
    func kebutuhanPerpanjangan(days: Double, expected: RenewalNeed) {
        let now = Self.start.addingTimeInterval(days * 86_400)
        #expect(RenewalPolicy.need(notBefore: Self.start, notAfter: Self.end, now: now) == expected)
    }

    @Test func tanpaNotBeforeMemakaiSisaTigaSetengahHari() {
        // Record lama tidak menyimpan not_before; anggap masa berlaku default 7 hari (ADR-0010).
        #expect(RenewalPolicy.need(notBefore: nil, notAfter: Self.end, now: Self.end.addingTimeInterval(-3.6 * 86_400)) == .none)
        #expect(RenewalPolicy.need(notBefore: nil, notAfter: Self.end, now: Self.end.addingTimeInterval(-3.4 * 86_400)) == .soon)
    }
}

import Foundation
import Testing
@testable import ANCore

@Suite("Identitas kartu fisik (FR-11, ADR-0031)")
struct CardIdentityTests {
    @Test func panjangPerTeknologi() {
        #expect(CardIdentity("iso14443a:04a1b2c3") != nil)
        #expect(CardIdentity("iso14443a:04A1B2C3D4E5F6")?.hex == "04a1b2c3d4e5f6")
        #expect(CardIdentity("iso14443a:04a1b2c3d4e5f6070809") != nil)
        #expect(CardIdentity("iso15693:e004010203040506")?.technology == .iso15693)
        #expect(CardIdentity("felica:0123456789abcdef") != nil)
        #expect(CardIdentity("iso7816:01") != nil)
        let invalid = ["", "iso14443a", "iso14443a:04a1b2c3d4", "iso15693:e0040102030405", "felica:zz",
                       "iso7816:", "iso9999:04a1b2c3", "iso7816:" + String(repeating: "ab", count: 33)]
        for text in invalid {
            #expect(CardIdentity(text) == nil, "\(text) seharusnya ditolak")
        }
    }

    @Test func deskripsiTidakMembocorkanIdentitas() {
        // CLAUDE.md aturan 6: identitas kartu tidak boleh ikut tercatat lewat interpolasi atau dump.
        let identity = CardIdentity("iso14443a:04a1b2c3d4e5f6")!
        var dumped = ""
        dump(identity, to: &dumped)
        for text in [String(describing: identity), String(reflecting: identity), "\(identity)", dumped] {
            #expect(!text.lowercased().contains("04a1b2c3d4e5f6"), "\(text)")
        }
    }
}

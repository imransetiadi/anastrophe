import Foundation
import Testing
@testable import ANCore

@Suite("Tautan undangan (FR-12, ADR-0033)")
struct InvitationLinkTests {
    static let token = String(repeating: "A", count: 42) + "w"

    @Test func tautanValidMemberiToken() {
        #expect(InvitationLink.token(from: URL(string: "https://contoh.test/i/\(Self.token)")!) == Self.token)
        #expect(InvitationLink.token(from: URL(string: "https://contoh.test/i/\(Self.token)/")!) == Self.token)
    }

    @Test(arguments: [
        "http://contoh.test/i/\(InvitationLinkTests.token)",
        "https://contoh.test/x/\(InvitationLinkTests.token)",
        "https://contoh.test/i/\(String(InvitationLinkTests.token.dropLast()))",
        "https://contoh.test/i/\(InvitationLinkTests.token)A",
        "https://contoh.test/i/\(String(InvitationLinkTests.token.dropLast()))+",
        "https://contoh.test/i/",
        "https://contoh.test/i/\(InvitationLinkTests.token)/lebih",
    ])
    func tautanTidakValidDitolak(link: String) {
        #expect(InvitationLink.token(from: URL(string: link)!) == nil)
    }

    @Test func bentukToken() {
        #expect(InvitationLink.isValidToken(Self.token))
        #expect(!InvitationLink.isValidToken(Self.token + "="))
        #expect(!InvitationLink.isValidToken(""))
    }
}

import Testing
@testable import ANCore

@Suite("Kode gedung (ADR-0044)")
struct SiteJoinCodeTests {
    /// Vektor yang sama dengan backend/internal/store/sitecode_test.go (Review Focus 3).
    static let vectors: [(String, String?)] = [
        ("7k2q-9xa4", "7K2Q9XA4"),
        (" 7K2Q 9XA4 ", "7K2Q9XA4"),
        ("OIL0-1234", "01101234"),
        ("7K2Q9XA", nil),
        ("7K2Q9XA4Z", nil),
        ("7K2Q9XU4", nil),
        ("", nil),
    ]

    @Test(arguments: SiteJoinCodeTests.vectors)
    func normalisasiSamaDenganServer(input: String, expected: String?) {
        #expect(SiteJoinCode.normalized(input) == expected)
    }

    @Test func tampilanBerkelompokEmpat() {
        #expect(SiteJoinCode.display("7K2Q9XA4") == "7K2Q-9XA4")
    }
}

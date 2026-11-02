import ANDesignSystem
import Foundation
import Testing

/// TC-UX-03 (NFR-A01): token warna lolos WCAG AA dan sama dengan tabel `pages/ios-app.md` §3.
@Suite("Kontras token warna")
struct ContrastTests {
    /// Rasio kontras WCAG 2.x antara dua warna sRGB 24 bit (urutan argumen bebas).
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            func linear(_ channel: UInt32) -> Double {
                let c = Double(channel & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb >> 16) + 0.7152 * linear(rgb >> 8) + 0.0722 * linear(rgb)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test func rumusKontrasSesuaiWCAG() {
        #expect(abs(Self.contrast(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(Self.contrast(0xFFFFFF, 0xFFFFFF) - 1) < 0.0001)
        // Abu-abu #767676 di atas putih: 4,54:1, nilai yang lazim dipakai sebagai batas AA.
        #expect(abs(Self.contrast(0x767676, 0xFFFFFF) - 4.54) < 0.01)
    }

    struct Pair: CustomTestStringConvertible, Sendable {
        let text: ANColorToken
        let surface: ANColorToken
        var testDescription: String { "\(text.name) di atas \(surface.name)" }
    }

    /// Pasangan teks/ikon dan permukaan yang dipakai UI (design system §3).
    static let pairs: [Pair] = {
        let texts: [ANColorToken] = [.foreground, .mutedForeground, .secondary, .success, .warning, .destructive, .primary]
        return texts.flatMap { text in [Pair(text: text, surface: .background), Pair(text: text, surface: .card)] }
            + [Pair(text: .onAccent, surface: .accent)]
    }()

    @Test(arguments: pairs)
    func pasanganTeksLolosAA(_ pair: Pair) {
        let light = Self.contrast(pair.text.light, pair.surface.light)
        let dark = Self.contrast(pair.text.dark, pair.surface.dark)
        #expect(light >= 4.5, "terang \(light)")
        #expect(dark >= 4.5, "gelap \(dark)")
    }

    #if os(macOS)
    /// `#filePath` = …/Packages/Tests/ANDesignSystemTests/<berkas> → empat tingkat ke atas = root repo.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    struct TableRow {
        let name: String
        let light: UInt32
        let dark: UInt32
        /// Rasio yang tertulis di kolom pemakaian: satu nilai (sama untuk kedua mode) atau terang/gelap.
        let ratios: [String]
    }

    /// Baris tabel §3 yang kolom pertamanya berawalan nama token dalam backtick.
    static func tableRows() throws -> [TableRow] {
        let text = try String(contentsOf: repoRoot.appending(path: "docs/design-system/anastrophe/pages/ios-app.md"), encoding: .utf8)
        let section = try #require(text.components(separatedBy: "## 3. Warna").dropFirst().first?.components(separatedBy: "\n## ").first)
        let hex = /`#([0-9A-Fa-f]{6})`/
        let ratio = /(\d+,\d)\s*:1/
        return try section.split(separator: "\n").compactMap { line -> TableRow? in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 5, let name = cells[1].firstMatch(of: /^`([A-Za-z]+)`/)?.1 else { return nil }
            let light = try #require(cells[2].firstMatch(of: hex)?.1, "hex terang \(name)")
            let dark = try #require(cells[3].firstMatch(of: hex)?.1, "hex gelap \(name)")
            return TableRow(name: String(name), light: try #require(UInt32(light, radix: 16)), dark: try #require(UInt32(dark, radix: 16)),
                            ratios: cells[4].matches(of: ratio).map { String($0.1) })
        }
    }

    @Test func tabelDesignSystemSamaDenganKode() throws {
        let rows = try Self.tableRows()
        #expect(Set(rows.map(\.name)) == Set(ANColorToken.all.map(\.name)))
        for row in rows {
            let token = try #require(ANColorToken.all.first { $0.name == row.name }, "\(row.name) tidak ada di kode")
            #expect(String(format: "%06X", row.light) == String(format: "%06X", token.light), "\(row.name) terang")
            #expect(String(format: "%06X", row.dark) == String(format: "%06X", token.dark), "\(row.name) gelap")
        }
    }

    @Test func rasioTabelSamaDenganHitungan() throws {
        let rows = try Self.tableRows()
        let annotated = rows.filter { !$0.ratios.isEmpty }
        // Token teks yang rasionya tertulis di tabel; parser yang gagal membaca anotasi tidak boleh lulus diam-diam.
        #expect(Set(annotated.map(\.name)) == ["foreground", "mutedForeground", "secondary", "onAccent", "success", "warning", "destructive"])
        for row in annotated {
            let token = try #require(ANColorToken.all.first { $0.name == row.name })
            let surface: ANColorToken = token == .onAccent ? .accent : .background
            func rounded(_ value: Double) -> String { String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") }
            let computed = [rounded(Self.contrast(token.light, surface.light)), rounded(Self.contrast(token.dark, surface.dark))]
            let expected = row.ratios.count == 1 ? [row.ratios[0], row.ratios[0]] : row.ratios
            #expect(expected == computed, "\(row.name): tabel \(row.ratios), hitungan \(computed)")
        }
    }
    #endif
}

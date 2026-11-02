#if os(macOS)
import Foundation
import Testing

/// Lint sumber (host saja) untuk anti-pola design system §8 (NFR-A01): ukuran font tetap dan animasi yang
/// tidak menghormati Reduce Motion.
@Suite("Lint aksesibilitas sumber")
struct AccessibilityLintTests {
    /// `#filePath` = …/Packages/Tests/ANDesignSystemTests/<berkas> → empat tingkat ke atas = root repo.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Semua berkas Swift app dan paket, dengan path relatif repo.
    static func sources() throws -> [(path: String, text: String)] {
        var result: [(String, String)] = []
        for folder in ["Packages/Sources", "App"] {
            let base = repoRoot.appending(path: folder)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = folder + url.path.dropFirst(base.path.count)
                result.append((relative, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return result
    }

    /// Pola ukuran font yang tidak ikut Dynamic Type (anti-pola §8). `Font.custom(_:size:)` dan `relativeTo:`
    /// ikut skala sehingga boleh (design system §2).
    func fixedFontViolations(_ text: String) -> [String] {
        [".system(size:", "fixedSize:"].filter(text.contains)
    }

    @Test func lintMenemukanBerkas() throws {
        // Path root yang salah tidak boleh membuat lint di bawah lulus tanpa memeriksa apa pun.
        #expect(try Self.sources().count >= 50)
    }

    @Test func fontTetapTerdeteksi() {
        #expect(fixedFontViolations("Text(\"A\").font(.system(size: 17))") == [".system(size:"])
        #expect(fixedFontViolations("Text(\"A\").font(.custom(\"Brand\", fixedSize: 12))") == ["fixedSize:"])
        #expect(fixedFontViolations("let f = Font.system(size: 20, weight: .bold)") == [".system(size:"])
    }

    @Test func fontYangIkutDynamicTypeBoleh() {
        // Design system §2: wordmark merek dengan relativeTo; Font.custom(_:size:) ikut skala body.
        #expect(fixedFontViolations("Text(\"A\").font(.custom(\"Brand\", size: 28, relativeTo: .title))").isEmpty)
        #expect(fixedFontViolations("Text(\"A\").font(Font.custom(\"Brand\", size: 17))").isEmpty)
        #expect(fixedFontViolations("Text(\"A\").font(.title2.weight(.semibold))").isEmpty)
    }

    @Test func tanpaUkuranFontTetap() throws {
        for (path, text) in try Self.sources() {
            #expect(fixedFontViolations(text).isEmpty, "\(path): \(fixedFontViolations(text)) — pakai text style Dynamic Type")
        }
    }

    /// Pola yang membuat teks atau kontrol memakai warna sistem, bukan token (ADR-0058):
    /// - nilai `LabeledContent(_:value:)`, judul `Section` berupa string, dan isi `header`/`footer`/`description` tanpa
    ///   `ANMutedText` memakai abu-abu sistem `secondaryLabel` (±3,4:1 di atas putih);
    /// - gaya terisi prominent tanpa warna eksplisit memberi teks putih di atas tint terang mode gelap (1,8:1);
    /// - `.secondary`/`.tertiary` sebagai warna teks adalah abu-abu sistem itu sendiri.
    ///
    /// Baris komentar diabaikan: dokumentasi boleh menyebut pola yang dilarang.
    func systemColorViolations(_ text: String) -> [String] {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let patterns: [(regex: String, name: String)] = [
            (#"LabeledContent\([^{\n]*value:"#, "LabeledContent(_:value:) — pakai ANValueRow"),
            (#"Section\((localized\(|")"#, "Section(<judul>) — pakai header: { ANMutedText(…) }"),
            (#"(header|footer|description): \{\s*+(?!ANMutedText\()"#, "header/footer/description tanpa ANMutedText"),
            (#"\.(borderedProminent|glassProminent)\b"#, "gaya terisi prominent — pakai gaya tombol design system"),
            (#"\.foreground(Style|Color)\(\.(secondary|tertiary)\)|\bColor\.(secondary|tertiary)\b"#, "warna teks abu-abu sistem — pakai ANColor"),
        ]
        return patterns.filter { code.range(of: $0.regex, options: .regularExpression) != nil }.map(\.name)
    }

    @Test func warnaSistemTerdeteksi() {
        #expect(systemColorViolations(#"LabeledContent(localized("detail.site"), value: card.siteName)"#).count == 1)
        #expect(systemColorViolations(#"Section(localized("detail.history")) {"#).count == 1)
        #expect(systemColorViolations(#"Section("Riwayat") {"#).count == 1)
        #expect(systemColorViolations("} header: {\n    Text(localized(\"help.section.devices\"))\n}").count == 1)
        #expect(systemColorViolations("} description: {\n    Text(localized(\"keys.empty.message\"))\n}").count == 1)
        #expect(systemColorViolations("Button(\"A\") {}.buttonStyle(.borderedProminent)").count == 1)
        #expect(systemColorViolations("Button(\"A\") {}.buttonStyle(.glassProminent)").count == 1)
        #expect(systemColorViolations("Text(\"A\").foregroundStyle(.secondary)").count == 1)
        #expect(systemColorViolations("Text(\"A\").foregroundColor(.tertiary)").count == 1)
        #expect(systemColorViolations("let c = Color.secondary").count == 1)
    }

    @Test func warnaTokenBoleh() {
        #expect(systemColorViolations("LabeledContent {\n    Text(value).foregroundStyle(ANColor.mutedForeground)\n} label: {").isEmpty)
        #expect(systemColorViolations(#"ANValueRow(localized("detail.site"), value: card.siteName)"#).isEmpty)
        #expect(systemColorViolations("Section {\n} header: {\n    ANMutedText(localized(\"help.section.devices\"))\n}").isEmpty)
        #expect(systemColorViolations("} description: {\n    ANMutedText(localized(\"keys.empty.message\"))\n}").isEmpty)
        #expect(systemColorViolations(".foregroundStyle(ANColor.secondary)").isEmpty)
        #expect(systemColorViolations("var description: String { name }").isEmpty)
        #expect(systemColorViolations("/// `LabeledContent(_:value:)` memakai abu-abu sistem.\n    // Section(\"Judul\") {").isEmpty)
    }

    @Test func tanpaWarnaTeksSistem() throws {
        for (path, text) in try Self.sources() {
            #expect(systemColorViolations(text).isEmpty, "\(path): \(systemColorViolations(text)) (ADR-0058)")
        }
    }

    @Test func animasiHanyaDenganReduceMotion() throws {
        for (path, text) in try Self.sources() {
            let animated = ["withAnimation", ".animation(", ".transition(", ".symbolEffect("].filter(text.contains)
            #expect(animated.isEmpty || text.contains("accessibilityReduceMotion"), "\(path): \(animated) tanpa accessibilityReduceMotion")
        }
    }
}
#endif

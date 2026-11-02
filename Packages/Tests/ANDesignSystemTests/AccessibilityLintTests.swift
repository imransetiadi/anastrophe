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

    @Test func animasiHanyaDenganReduceMotion() throws {
        for (path, text) in try Self.sources() {
            let animated = ["withAnimation", ".animation(", ".transition(", ".symbolEffect("].filter(text.contains)
            #expect(animated.isEmpty || text.contains("accessibilityReduceMotion"), "\(path): \(animated) tanpa accessibilityReduceMotion")
        }
    }
}
#endif

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

    @Test func lintMenemukanBerkas() throws {
        // Path root yang salah tidak boleh membuat lint di bawah lulus tanpa memeriksa apa pun.
        #expect(try Self.sources().count >= 50)
    }

    @Test func tanpaUkuranFontTetap() throws {
        for (path, text) in try Self.sources() {
            for pattern in [".system(size:", "Font.custom(", ".font(.custom("] {
                #expect(!text.contains(pattern), "\(path): \(pattern) — pakai text style Dynamic Type")
            }
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

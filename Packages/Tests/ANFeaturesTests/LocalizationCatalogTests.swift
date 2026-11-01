#if os(macOS)
import Foundation
import Testing

/// Lint sumber (host saja): string UI tersedia dalam ID dan EN (CLAUDE.md, Bahasa), dan setiap
/// kunci `localized("…")` yang dipakai kode benar-benar ada di katalog.
@Suite("Katalog string ID/EN")
struct LocalizationCatalogTests {
    /// `#filePath` = …/Packages/Tests/ANFeaturesTests/<berkas> → empat tingkat ke atas = root repo.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func strings(_ relativePath: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: repoRoot.appending(path: relativePath))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: [String: Any]])
    }

    @Test(arguments: ["Packages/Sources/ANFeatures/Resources/Localizable.xcstrings", "App/InfoPlist.xcstrings"])
    func setiapStringPunyaIDdanEN(path: String) throws {
        for (key, entry) in try Self.strings(path) {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in ["id", "en"] {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                #expect(unit?["state"] as? String == "translated" && !value.isEmpty, "\(path): \(key) tanpa terjemahan \(language)")
            }
        }
    }

    @Test func setiapKunciYangDipakaiAdaDiKatalog() throws {
        let catalog = Set(try Self.strings("Packages/Sources/ANFeatures/Resources/Localizable.xcstrings").keys)
        let sources = Self.repoRoot.appending(path: "Packages/Sources/ANFeatures")
        let pattern = try NSRegularExpression(pattern: #"localized\("([^"\\]+)"\)"#)
        var used = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { used.insert(String(text[range])) }
            }
        }
        #expect(!used.isEmpty)
        let missing = used.subtracting(catalog).sorted()
        #expect(missing.isEmpty, "kunci tanpa terjemahan: \(missing)")
    }
}
#endif

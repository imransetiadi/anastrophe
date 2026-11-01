import Foundation
import Testing

/// Katalog string ID/EN (CLAUDE.md) dan teks presentasi tanpa jargon (FR-26, TC-PRSN-17).
@Suite("Katalog string")
struct StringCatalogTests {
    struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String }
                let stringUnit: Unit
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    static func load() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/ANFeatures/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test func setiapStringPunyaIdDanEn() throws {
        let catalog = try Self.load()
        #expect(!catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            let id = entry.localizations?["id"]?.stringUnit.value ?? ""
            let en = entry.localizations?["en"]?.stringUnit.value ?? ""
            #expect(!id.isEmpty && !en.isEmpty, "\(key) belum lengkap ID/EN")
        }
    }

    @Test func teksTambahKartuTanpaJargon() throws {
        // Alur Tambah Kartu (ADR-0043) memakai aturan teks presentasi: tanpa istilah teknis.
        let catalog = try Self.load()
        let flow = catalog.strings.filter { $0.key.hasPrefix("add.") }
        #expect(flow.count >= 25)
        for (key, entry) in flow {
            for (_, localization) in entry.localizations ?? [:] {
                let text = localization.stringUnit.value.uppercased()
                #expect(!["NFC", "HCE", "APDU"].contains { text.contains($0) }, "\(key) memuat istilah teknis")
            }
        }
    }

    @Test func teksPresentasiTanpaJargon() throws {
        let catalog = try Self.load()
        let presentation = catalog.strings.filter { $0.key.hasPrefix("present.") }
        #expect(presentation.count >= 8)
        for (key, entry) in presentation {
            for (_, localization) in entry.localizations ?? [:] {
                let text = localization.stringUnit.value.uppercased()
                #expect(!["NFC", "HCE", "APDU"].contains { text.contains($0) }, "\(key) memuat istilah teknis")
            }
        }
    }
}

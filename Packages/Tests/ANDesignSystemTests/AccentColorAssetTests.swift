#if os(macOS)
import ANDesignSystem
import Foundation
import Testing

/// Tint app (ADR-0058): aset AccentColor app sama dengan token `secondary`, sehingga alert, share sheet, dan menu yang
/// tidak membaca `.tint` SwiftUI memakai warna yang sama dengan app, dan proyek memakai aset itu sebagai tint global.
@Suite("Aset AccentColor sama dengan token")
struct AccentColorAssetTests {
    /// `#filePath` = …/Packages/Tests/ANDesignSystemTests/<berkas> → empat tingkat ke atas = root repo.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Komponen warna aset: `0xNN`, bilangan bulat 0–255, atau pecahan 0–1.
    static func channel(_ value: String) throws -> UInt32 {
        if value.hasPrefix("0x") { return try #require(UInt32(value.dropFirst(2), radix: 16)) }
        let number = try #require(Double(value))
        return UInt32((value.contains(".") ? number * 255 : number).rounded())
    }

    /// Warna sRGB 24 bit per tampilan (`any` = terang, `dark` = gelap) dari `Contents.json` sebuah colorset.
    static func colors(ofColorSet name: String) throws -> [String: UInt32] {
        let url = repoRoot.appending(path: "App/Assets.xcassets/\(name).colorset/Contents.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var result: [String: UInt32] = [:]
        for entry in try #require(json["colors"] as? [[String: Any]]) {
            let appearance = (entry["appearances"] as? [[String: String]])?.first { $0["appearance"] == "luminosity" }?["value"] ?? "any"
            let color = try #require(entry["color"] as? [String: Any])
            #expect(color["color-space"] as? String == "srgb", "\(name) \(appearance): ruang warna harus sRGB seperti token")
            let components = try #require(color["components"] as? [String: String])
            let (red, green, blue) = try (channel(#require(components["red"])), channel(#require(components["green"])), channel(#require(components["blue"])))
            #expect(components["alpha"].flatMap(Double.init) == 1, "\(name) \(appearance): alpha harus 1")
            result[appearance] = red << 16 | green << 8 | blue
        }
        return result
    }

    @Test func komponenAsetTerbaca() throws {
        #expect(try Self.channel("0x1E") == 0x1E)
        #expect(try Self.channel("147") == 147)
        #expect(try Self.channel("0.541") == 138)
    }

    @Test func accentColorSamaDenganTokenSecondary() throws {
        let colors = try Self.colors(ofColorSet: "AccentColor")
        #expect(colors == ["any": ANColorToken.secondary.light, "dark": ANColorToken.secondary.dark])
    }

    @Test func proyekMemakaiAccentColorSebagaiTintGlobal() throws {
        let project = try String(contentsOf: Self.repoRoot.appending(path: "Anastrophe.xcodeproj/project.pbxproj"), encoding: .utf8)
        // Satu per konfigurasi target app (Debug dan Release); target UI test tidak punya katalog aset.
        #expect(project.components(separatedBy: "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;").count - 1 == 2)
    }
}
#endif

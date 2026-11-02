import SwiftUI

/// Satu token warna design system (`docs/design-system/anastrophe/pages/ios-app.md` §3): nilai sRGB 24 bit
/// untuk mode terang dan gelap. Nilainya data agar kontras WCAG dan kesamaan dengan tabel bisa diuji
/// (`ANDesignSystemTests`, TC-UX-03).
public struct ANColorToken: Sendable, Equatable {
    public let name: String
    public let light: UInt32
    public let dark: UInt32

    public static let background = ANColorToken(name: "background", light: 0xF8FAFC, dark: 0x020617)
    public static let foreground = ANColorToken(name: "foreground", light: 0x020617, dark: 0xF8FAFC)
    public static let card = ANColorToken(name: "card", light: 0xFFFFFF, dark: 0x0F172A)
    public static let mutedForeground = ANColorToken(name: "mutedForeground", light: 0x475569, dark: 0x94A3B8)
    public static let primary = ANColorToken(name: "primary", light: 0x0F172A, dark: 0xE2E8F0)
    public static let secondary = ANColorToken(name: "secondary", light: 0x1E3A8A, dark: 0x93C5FD)
    public static let accent = ANColorToken(name: "accent", light: 0xA16207, dark: 0xEAB308)
    public static let onAccent = ANColorToken(name: "onAccent", light: 0xFFFFFF, dark: 0x020617)
    public static let success = ANColorToken(name: "success", light: 0x15803D, dark: 0x4ADE80)
    public static let warning = ANColorToken(name: "warning", light: 0xB45309, dark: 0xFBBF24)
    public static let destructive = ANColorToken(name: "destructive", light: 0xDC2626, dark: 0xF87171)

    public static let all: [ANColorToken] = [
        background, foreground, card, mutedForeground, primary, secondary, accent, onAccent, success, warning, destructive,
    ]

    #if canImport(UIKit)
    /// Warna UIKit dinamis untuk kontrol UIKit design system, mis. placeholder `ANTextField`.
    public var uiColor: UIColor {
        let (light, dark) = (light, dark)
        return UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) }
    }
    #endif

    /// Warna dinamis yang mengikuti mode terang/gelap.
    public var color: Color {
        #if canImport(UIKit)
        return Color(uiColor)
        #else
        let (light, dark) = (light, dark)
        return Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light) })
        #endif
    }
}

/// Warna token untuk view (light/dark, WCAG AA).
public enum ANColor {
    public static let background = ANColorToken.background.color
    public static let foreground = ANColorToken.foreground.color
    public static let card = ANColorToken.card.color
    public static let mutedForeground = ANColorToken.mutedForeground.color
    public static let primary = ANColorToken.primary.color
    public static let secondary = ANColorToken.secondary.color
    public static let accent = ANColorToken.accent.color
    public static let onAccent = ANColorToken.onAccent.color
    public static let success = ANColorToken.success.color
    public static let warning = ANColorToken.warning.color
    public static let destructive = ANColorToken.destructive.color
}

#if canImport(UIKit)
import UIKit
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#else
import AppKit
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif

/// Tombol aksi utama (satu per layar). Minimal 44 pt (50 pt dengan `.controlSize(.large)`, lihat `ANTouchTarget`), ikut
/// Dynamic Type. Gaya tombol lain ada di `ControlStyles.swift`.
public struct ANPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    /// Membaca `isEnabled` agar tombol nonaktif tidak tampak sama dengan yang aktif.
    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            configuration.label
                .font(.headline)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: ANTouchTarget.minHeight(for: controlSize))
                .foregroundStyle(ANColor.onAccent)
                .background(ANColor.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 12))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

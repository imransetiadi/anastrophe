import SwiftUI

/// Token warna dari `docs/design-system/anastrophe/pages/ios-app.md` §3 (light/dark, WCAG AA).
public enum ANColor {
    public static let background = dynamic(light: 0xF8FAFC, dark: 0x020617)
    public static let foreground = dynamic(light: 0x020617, dark: 0xF8FAFC)
    public static let card = dynamic(light: 0xFFFFFF, dark: 0x0F172A)
    public static let mutedForeground = dynamic(light: 0x475569, dark: 0x94A3B8)
    public static let primary = dynamic(light: 0x0F172A, dark: 0xE2E8F0)
    public static let secondary = dynamic(light: 0x1E3A8A, dark: 0x93C5FD)
    public static let accent = dynamic(light: 0xA16207, dark: 0xEAB308)
    public static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x020617)
    public static let success = dynamic(light: 0x15803D, dark: 0x4ADE80)
    public static let warning = dynamic(light: 0xB45309, dark: 0xFBBF24)
    public static let destructive = dynamic(light: 0xDC2626, dark: 0xF87171)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #else
        Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light) })
        #endif
    }
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

/// Tombol aksi utama (satu per layar). Minimal 44 pt, ikut Dynamic Type.
public struct ANPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(ANColor.onAccent)
            .background(ANColor.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 12))
    }
}

import SwiftUI

/// Tinggi minimum area ketuk kontrol (design system §4): 44 pt, atau 50 pt dengan `.controlSize(.large)`. Ukuran besar
/// dipakai di tempat yang diperkecil sistem, mis. lembar setengah tinggi iOS 26 yang tampil ±96 %, sehingga kontrol 44 pt
/// terukur ±42 pt di layar.
enum ANTouchTarget {
    static let minimum: CGFloat = 44

    static func minHeight(for size: ControlSize) -> CGFloat {
        switch size {
        case .large, .extraLarge: 50
        default: minimum
        }
    }
}

/// Tombol teks sekunder: aksi kedua atau pembatalan di bawah aksi utama, mis. "Batal", "Coba lagi", "Bukan gedung saya",
/// dan tautan "Buka Pengaturan". Warna `secondary` (tautan/info, §3). Bingkai minimum dan `contentShape` dipasang pada
/// label di dalam gaya, sehingga seluruh bingkai menjadi area ketuk tombol itu sendiri, bukan hanya teksnya (§4, NFR-A01).
public struct ANSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }

    /// Membaca `isEnabled` agar tombol nonaktif tidak tampak sama dengan yang aktif.
    private struct SecondaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            configuration.label
                .font(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: ANTouchTarget.minHeight(for: controlSize))
                .contentShape(.rect)
                .foregroundStyle(ANColor.secondary)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Tombol aksi ringkas di dalam baris, mis. "Gunakan" di daftar kartu: teks `onAccent` di atas `accent` seperti tombol
/// utama (§3), lebar mengikuti teks, dan tinggi minimum di dalam gaya sehingga area ketuknya sendiri ≥ 44 pt (§4).
public struct ANCompactAccentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CompactAccentButtonBody(configuration: configuration)
    }

    private struct CompactAccentButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            let minHeight = ANTouchTarget.minHeight(for: controlSize)
            configuration.label
                .font(.headline)
                .padding(.horizontal, 14)
                .frame(minWidth: minHeight, minHeight: minHeight)
                .foregroundStyle(ANColor.onAccent)
                .background(ANColor.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .capsule)
                .contentShape(.rect)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

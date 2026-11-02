#if os(macOS)
import AppKit
@testable import ANDesignSystem
import SwiftUI
import Testing

/// Area ketuk gaya kontrol design system (§4, NFR-A01): bingkai minimum ada di dalam gaya, sehingga tombol itu sendiri,
/// tanpa bingkai tambahan di luar, sudah ≥ 44 pt. Ukuran diukur lewat hosting SwiftUI di host; area ketuk nyata di iPhone
/// diperiksa `AnastropheUITests` (TC-UX-04).
@Suite("Area ketuk gaya kontrol")
@MainActor
struct ControlStyleTests {
    /// Ukuran yang dipilih view bila diberi lebar 320 pt dan tinggi longgar.
    func size(of view: some View) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 320, height: 1000))
    }

    @Test func tinggiMinimumMengikutiUkuranKontrol() {
        #expect(ANTouchTarget.minHeight(for: .mini) == 44)
        #expect(ANTouchTarget.minHeight(for: .small) == 44)
        #expect(ANTouchTarget.minHeight(for: .regular) == 44)
        #expect(ANTouchTarget.minHeight(for: .large) == 50)
        #expect(ANTouchTarget.minHeight(for: .extraLarge) == 50)
    }

    @Test func tombolSekunderMinimal44ptSelebarWadah() {
        let size = size(of: Button("Batal") {}.buttonStyle(ANSecondaryButtonStyle()))
        #expect(size.height >= 44)
        #expect(size.width == 320)
    }

    @Test func tombolAksenRingkasMinimal44ptSelebarTeks() {
        let size = size(of: Button("Gunakan") {}.buttonStyle(ANCompactAccentButtonStyle()))
        #expect(size.height >= 44)
        #expect(size.width >= 44 && size.width < 320)
    }

    @Test func ukuranKontrolBesarMemberi50pt() {
        #expect(size(of: Button("Batal") {}.buttonStyle(ANSecondaryButtonStyle()).controlSize(.large)).height >= 50)
        #expect(size(of: Button("Gunakan") {}.buttonStyle(ANCompactAccentButtonStyle()).controlSize(.large)).height >= 50)
        #expect(size(of: Button("Selesai") {}.buttonStyle(ANPrimaryButtonStyle()).controlSize(.large)).height >= 50)
        #expect(size(of: Button("Selesai") {}.buttonStyle(ANPrimaryButtonStyle())).height >= 44)
    }

    @Test func tinggiFieldMinimal44ptDanTumbuhBersamaTeks() {
        // Baris `body` bawaan (±22 pt) + padding 2 × 10 pt masih di bawah 44 pt → 44 pt.
        #expect(ANTextFieldMetrics.height(lineHeight: 20.3) == 44)
        // Teks besar (Dynamic Type): tinggi baris + padding, dibulatkan ke atas, agar teks tidak terpotong.
        #expect(ANTextFieldMetrics.height(lineHeight: 30.2) == 51)
        #expect(ANTextFieldMetrics.height(lineHeight: 64) == 84)
    }

    @Test func fieldTeksMinimal44pt() {
        #expect(size(of: ANTextField("Kode", text: .constant(""), prompt: "XXXX-XXXX", kind: .code) {}).height >= 44)
    }
}
#endif

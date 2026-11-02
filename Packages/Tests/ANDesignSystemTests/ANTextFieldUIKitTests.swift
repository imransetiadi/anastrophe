#if canImport(UIKit)
@testable import ANDesignSystem
import SwiftUI
import Testing
import UIKit

/// Perilaku `ANTextField` di iOS: `UITextField` itu sendiri ≥ 44 pt (area ketuk = elemen aksesibilitas, design system §4),
/// ketikan mengisi binding, Return menjalankan aksi kirim, dan field tumbuh bersama Dynamic Type. Berjalan di suite paket
/// simulator; `swift test` di host (macOS) melewati berkas ini.
@Suite("Field teks iOS")
@MainActor
struct ANTextFieldUIKitTests {
    /// Penampung nilai binding dan jumlah kirim; hanya disentuh di main thread.
    final class Box: @unchecked Sendable {
        var text = ""
        var submitted = 0
    }

    /// Menampilkan field di jendela agar SwiftUI membuat `UITextField`-nya (tanpa jendela, view UIKit tidak dibuat), lalu
    /// mengembalikannya. Proses test paket tidak punya `UIApplication` maupun window scene, jadi jendela sengaja dibuat
    /// dengan `init(frame:)` yang usang sejak iOS 26 (satu peringatan, hanya di test). Jendela dikembalikan agar tetap hidup.
    func render(_ box: Box, kind: ANTextField.Kind, size: DynamicTypeSize = .large) throws -> (UIWindow, ANPaddedUITextField) {
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = ANTextField("Kode gedung", text: binding, prompt: "XXXX-XXXX", kind: kind, identifier: "uji.field") {
            box.submitted += 1
        }
        .frame(width: 320)
        .environment(\.dynamicTypeSize, size)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        var field: ANPaddedUITextField?
        for _ in 0..<20 where field == nil {
            controller.view.layoutIfNeeded()
            field = Self.descendants(of: ANPaddedUITextField.self, in: controller.view).first
            if field == nil { RunLoop.main.run(until: .now.addingTimeInterval(0.05)) }
        }
        return (window, try #require(field))
    }

    static func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        view.subviews.flatMap { sub -> [T] in ((sub as? T).map { [$0] } ?? []) + descendants(of: type, in: sub) }
    }

    @Test func fieldItuSendiriMinimal44ptDenganLabelDanIdentifier() throws {
        let (host, field) = try render(Box(), kind: .url)
        defer { withExtendedLifetime(host) {} }
        #expect(field.bounds.height >= 44)
        #expect(field.bounds.width == 320)
        #expect(field.accessibilityLabel == "Kode gedung")
        #expect(field.accessibilityIdentifier == "uji.field")
        #expect(field.placeholder == "XXXX-XXXX")
    }

    @Test func ketikanMengisiBindingDanReturnMengirim() throws {
        let box = Box()
        let (host, field) = try render(box, kind: .code)
        defer { withExtendedLifetime(host) {} }
        field.text = "AB12CD34"
        // Proses test paket tidak punya `UIApplication`, jadi `sendActions` tidak mengirim apa pun; aksi `.editingChanged`
        // yang terdaftar dipanggil langsung, seperti yang dilakukan UIKit saat pengguna mengetik.
        let actions = field.allTargets.flatMap { target in
            (field.actions(forTarget: target.base, forControlEvent: .editingChanged) ?? []).map { (target.base as AnyObject, Selector($0)) }
        }
        #expect(actions.count == 1)
        for (target, action) in actions { _ = target.perform(action, with: field) }
        #expect(box.text == "AB12CD34")
        #expect(field.delegate?.textFieldShouldReturn?(field) == false)
        #expect(box.submitted == 1)
    }

    @Test func jenisMenentukanKeyboardDanReturn() throws {
        let (codeHost, code) = try render(Box(), kind: .code)
        defer { withExtendedLifetime(codeHost) {} }
        #expect(code.keyboardType == .asciiCapable)
        #expect(code.autocapitalizationType == .allCharacters)
        #expect(code.returnKeyType == .continue)
        #expect(code.autocorrectionType == .no)
        let (urlHost, url) = try render(Box(), kind: .url)
        defer { withExtendedLifetime(urlHost) {} }
        #expect(url.keyboardType == .URL)
        #expect(url.autocapitalizationType == UITextAutocapitalizationType.none)
        #expect(url.returnKeyType == .go)
    }

    @Test func fieldTumbuhBersamaDynamicType() throws {
        let (smallHost, small) = try render(Box(), kind: .code)
        defer { withExtendedLifetime(smallHost) {} }
        let (largeHost, large) = try render(Box(), kind: .code, size: .accessibility5)
        defer { withExtendedLifetime(largeHost) {} }
        #expect(large.adjustsFontForContentSizeCategory)
        #expect((large.font?.pointSize ?? 0) > (small.font?.pointSize ?? 0))
        #expect(large.bounds.height > small.bounds.height)
        #expect(large.bounds.height >= (large.font?.lineHeight ?? 0))
    }
}
#endif

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Field teks satu baris design system dengan area ketuk ≥ 44 pt (§4). `TextField` SwiftUI selalu setinggi teksnya
/// (22–26 pt; `.roundedBorder` 34 pt, juga dengan `controlSize` besar), dan bingkai atau padding di luarnya tidak memperbesar
/// field yang bisa diketuk maupun elemen aksesibilitasnya (terukur di audit ADR-0057). Karena itu di iOS field ini memakai
/// `UITextField` yang tingginya sendiri ≥ 44 pt dengan padding di dalam field. Latar `card`, garis tepi dan placeholder
/// `mutedForeground` (batas field ≥ 3:1, WCAG 1.4.11; placeholder ≥ 4,5:1, ADR-0058), dan huruf ikut Dynamic Type.
public struct ANTextField: View {
    /// Jenis isian: menentukan huruf, keyboard, huruf kapital, dan tombol Return.
    public enum Kind: Sendable {
        /// Kode huruf-angka, mis. kode gedung: huruf monospace `title3`, kapital semua, keyboard ASCII, Return "Lanjut".
        case code
        /// Alamat web, mis. tautan undangan: huruf `body`, tanpa kapital, keyboard URL, Return "Buka".
        case url
    }

    private let title: String
    @Binding private var text: String
    private let prompt: String
    private let kind: Kind
    private let identifier: String?
    private let onSubmit: () -> Void

    /// `title` menjadi label VoiceOver, `prompt` teks contoh di dalam field, dan `identifier` dipasang pada field itu sendiri.
    public init(_ title: String, text: Binding<String>, prompt: String, kind: Kind, identifier: String? = nil,
                onSubmit: @escaping () -> Void) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.kind = kind
        self.identifier = identifier
        self.onSubmit = onSubmit
    }

    public var body: some View {
        field
            .background(ANColor.card, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(ANColor.mutedForeground, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var field: some View {
        #if canImport(UIKit)
        PaddedTextField(title: title, text: $text, prompt: prompt, kind: kind, identifier: identifier, onSubmit: onSubmit)
        #else
        // Host (macOS) hanya untuk `swift test`; app iOS memakai cabang UIKit di atas.
        TextField(title, text: $text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .padding(.horizontal, ANTextFieldMetrics.horizontalPadding)
            .frame(minHeight: ANTouchTarget.minimum)
            .onSubmit(onSubmit)
            .accessibilityIdentifier(identifier ?? "")
        #endif
    }
}

/// Padding field dan tinggi yang dihasilkannya.
enum ANTextFieldMetrics {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 10

    /// Tinggi field untuk satu baris teks: tinggi baris ditambah padding atas-bawah, minimal 44 pt. Tumbuh bersama
    /// Dynamic Type sehingga teks besar tidak terpotong.
    static func height(lineHeight: CGFloat) -> CGFloat {
        max(ANTouchTarget.minimum, (lineHeight + 2 * verticalPadding).rounded(.up))
    }
}

#if canImport(UIKit)
/// `UITextField` dengan padding di dalam field, sehingga area ketuk dan elemen aksesibilitasnya adalah seluruh kotak.
final class ANPaddedUITextField: UITextField {
    private let insets = UIEdgeInsets(top: 0, left: ANTextFieldMetrics.horizontalPadding, bottom: 0,
                                      right: ANTextFieldMetrics.horizontalPadding)

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: insets) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: insets) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.inset(by: insets) }

    var preferredHeight: CGFloat { ANTextFieldMetrics.height(lineHeight: font?.lineHeight ?? 22) }
}

private struct PaddedTextField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    let prompt: String
    let kind: ANTextField.Kind
    let identifier: String?
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> ANPaddedUITextField {
        let field = ANPaddedUITextField()
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        switch kind {
        case .code:
            field.autocapitalizationType = .allCharacters
            field.keyboardType = .asciiCapable
            field.returnKeyType = .continue
        case .url:
            field.autocapitalizationType = .none
            field.keyboardType = .URL
            field.returnKeyType = .go
        }
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: ANPaddedUITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.accessibilityLabel = title
        field.accessibilityIdentifier = identifier
        field.isEnabled = context.environment.isEnabled
        // Ukuran huruf mengikuti Dynamic Type lingkungan SwiftUI, sama dengan teks lain di layar.
        let font = Self.font(for: kind, size: context.environment.dynamicTypeSize)
        if field.font != font {
            field.font = font
            field.invalidateIntrinsicContentSize()
        }
        // Warna placeholder sistem hanya 1,7:1 di atas `card`; token `mutedForeground` dengan huruf field (ADR-0058).
        field.attributedPlaceholder = NSAttributedString(string: prompt, attributes: [.foregroundColor: ANColorToken.mutedForeground.uiColor, .font: font])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: ANPaddedUITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: field.preferredHeight)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Huruf field untuk ukuran Dynamic Type `size`. Kode memakai monospace dengan skala `title3`.
    static func font(for kind: ANTextField.Kind, size: DynamicTypeSize) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        switch kind {
        case .code:
            let base = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
            return UIFontMetrics(forTextStyle: .title3)
                .scaledFont(for: .monospacedSystemFont(ofSize: base.pointSize, weight: .regular), compatibleWith: traits)
        case .url:
            return .preferredFont(forTextStyle: .body, compatibleWith: traits)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PaddedTextField

        init(parent: PaddedTextField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        /// Seperti `TextField` SwiftUI: Return menutup keyboard lalu menjalankan aksi kirim.
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            parent.onSubmit()
            return false
        }
    }
}
#endif

import SwiftUI

/// Teks sekunder bertoken `mutedForeground` untuk judul dan catatan seksi `List` serta deskripsi `ContentUnavailableView`
/// (ADR-0058). Tanpa warna eksplisit sistem memakai abu-abu `secondaryLabel`, ±3,4:1 di atas `background`; token ini
/// 7,2:1 / 7,9:1. Huruf tetap mengikuti tempatnya (gaya judul seksi atau deskripsi sistem).
public struct ANMutedText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .foregroundStyle(ANColor.mutedForeground)
    }
}

/// Baris label–nilai `List` dengan nilai bertoken `mutedForeground` (ADR-0058). `LabeledContent(_:value:)` memakai
/// abu-abu sistem untuk nilai, ±3,4:1 di atas `card`. VoiceOver tetap membaca label dan nilai sebagai satu elemen.
public struct ANValueRow: View {
    private let title: String
    private let value: String

    public init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(ANColor.mutedForeground)
        } label: {
            Text(title)
        }
    }
}

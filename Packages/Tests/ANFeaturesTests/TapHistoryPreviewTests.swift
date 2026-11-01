import ANCore
import Foundation
import Testing
@testable import ANFeatures

/// ADR-0030: detail menampilkan lima tap terbaru; sisanya lewat "Lihat semua".
@Suite("Ringkasan riwayat di detail (ADR-0030, FR-30)")
struct TapHistoryPreviewTests {
    /// Terbaru dulu, seperti urutan dari store.
    func entries(_ count: Int) -> [TapEntry] {
        let card = UUID()
        return (0..<count).map { TapEntry(cardID: card, date: Date(timeIntervalSince1970: Double(1_000_000 - $0 * 3_600)), channel: .ble, granted: $0 % 3 != 0, denyReason: $0 % 3 == 0 ? .zoneNotAllowed : nil) }
    }

    @Test func riwayatPanjangLimaTerbaruDanLihatSemua() {
        let all = entries(25)
        let preview = TapHistoryPreview(all)
        #expect(preview.inline == Array(all.prefix(5)))
        #expect(preview.showsAll)
        #expect(preview.total == 25)
    }

    @Test func riwayatPendekTanpaLihatSemua() {
        #expect(TapHistoryPreview(entries(5)).inline.count == 5)
        #expect(!TapHistoryPreview(entries(5)).showsAll)
        #expect(TapHistoryPreview(entries(3)).inline.count == 3)
        #expect(TapHistoryPreview([]).inline.isEmpty)
        #expect(TapHistoryPreview(entries(6)).showsAll)
    }
}

import XCTest

/// Alur fungsional layar Kunci atas data demo (`-ANDemo`): tanpa jaringan dan tanpa presentasi nyata, karena
/// lembar presentasi demo hanya memakai launcher bernaskah (CLAUDE.md aturan 4; ADR-0057).
final class KunciFungsionalTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// "Gunakan" adalah tombol bergaya kustom di dalam `NavigationLink` baris daftar. Ketukannya harus membuka
    /// lembar presentasi, bukan detail kartu yang menjadi tujuan baris.
    @MainActor func testGunakanDiDaftarMembukaLembarPresentasi() {
        let app = AccessibilityAudit.launch(.list, variant: AuditVariant())
        XCTAssertTrue(AccessibilityAudit.element("keys.list", in: app).waitForExistence(timeout: 10), "daftar kartu tidak muncul")

        // Bahasa ID dipaksa saat peluncuran (`AuditVariant()`), jadi labelnya "Gunakan".
        let use = app.buttons["Gunakan"].firstMatch
        XCTAssertTrue(use.waitForExistence(timeout: 10), "tombol Gunakan tidak ada di daftar")
        XCTAssertTrue(use.isHittable, "tombol Gunakan tidak bisa diketuk")
        use.tap()

        XCTAssertTrue(AccessibilityAudit.element("present.cancel", in: app).waitForExistence(timeout: 10),
                      "lembar presentasi tidak terbuka sesudah mengetuk Gunakan")
        XCTAssertFalse(AccessibilityAudit.element("detail.list", in: app).exists, "ketukan Gunakan membuka detail kartu, bukan lembar presentasi")
        app.terminate()
    }

    /// Baris FAQ Bantuan adalah satu tombol buka-tutup seluas sel. Ketukan di area kosong sel, di luar teks pertanyaan
    /// dan jauh dari penunjuk (chevron) bawaan sistem di ujung kanan, membuka jawaban. Ini dasar pengecualian penunjuk
    /// dari cek ukuran target sentuh (`AccessibilityAudit.disclosureRowPrefix`): area ketuk yang sebenarnya adalah sel
    /// (≥ 44 pt), bukan penunjuk. Baris yang dipakai satu baris teks, jadi bingkai teksnya lebih rendah dari sel.
    @MainActor func testBarisFAQDiketukDiLuarTeksMembukaJawaban() {
        let app = AccessibilityAudit.launch(.help, variant: AuditVariant())
        let list = AccessibilityAudit.element("help.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 10), "daftar Bantuan tidak muncul")

        let row = app.buttons["help.faq.delete"].firstMatch
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 6 {
            list.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(row.isHittable, "baris FAQ hapus kartu tidak terjangkau")
        let rowFrame = row.frame
        guard let cell = app.cells.allElementsBoundByIndex.map(\.frame).first(where: { $0.contains(CGPoint(x: rowFrame.midX, y: rowFrame.midY)) }) else {
            return XCTFail("sel baris FAQ tidak ditemukan")
        }
        XCTAssertGreaterThanOrEqual(cell.height, AccessibilityAudit.minimumTarget - AccessibilityAudit.tolerance, "sel FAQ lebih rendah dari 44 pt")

        // Titik di dalam sel, di bawah teks pertanyaan bila masih ada ruang, dan 60 pt dari tepi kanan (di luar penunjuk).
        let target = CGPoint(x: cell.maxX - 60, y: min(cell.maxY - 4, max(rowFrame.maxY + 4, cell.midY)))
        let tapX = (target.x - cell.minX) / cell.width
        let tapY = (target.y - cell.minY) / cell.height
        print("FAQ-TAP | sel=\(cell) | teks=\(rowFrame) | titik=\(target)")

        // Jawaban membawa identifier grup yang sama sebagai teks statis, dan hanya ada saat grup terbuka.
        let answers = app.staticTexts.matching(identifier: "help.faq.delete")
        XCTAssertEqual(answers.count, 0, "jawaban sudah terbuka sebelum diketuk")
        app.cells.allElementsBoundByIndex.first { $0.frame == cell }?
            .coordinate(withNormalizedOffset: CGVector(dx: tapX, dy: tapY)).tap()
        XCTAssertTrue(answers.firstMatch.waitForExistence(timeout: 5), "ketukan di area kosong sel tidak membuka jawaban")
        app.terminate()
    }
}

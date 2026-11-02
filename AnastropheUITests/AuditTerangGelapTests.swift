import XCTest

/// Audit setiap keadaan layar dalam mode terang lalu gelap, ukuran teks bawaan, bahasa ID (ADR-0057).
final class AuditTerangGelapTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
        await MainActor.run { XCUIDevice.shared.appearance = .light }
        addTeardownBlock { await MainActor.run { XCUIDevice.shared.appearance = .light } }
    }

    @MainActor
    private func run(_ screen: AuditScreen, file: StaticString = #filePath, line: UInt = #line) {
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            let label = appearance == .dark ? "gelap" : "terang"
            guard let app = AccessibilityAudit.open(screen, variant: AuditVariant(), file: file, line: line) else { continue }
            AccessibilityAudit.auditPages(app, screen: screen, context: "\(screen) \(label)", pages: screen.scrollPages, file: file, line: line)
            app.terminate()
        }
    }

    @MainActor func testDaftarKartu() { run(.list) }
    @MainActor func testDaftarKosong() { run(.empty) }
    @MainActor func testDetailKartu() { run(.detail) }
    @MainActor func testDetailDitangguhkan() { run(.detailSuspended) }
    @MainActor func testRiwayatLengkap() { run(.history) }
    @MainActor func testPresentasiMenunggu() { run(.presentation) }
    @MainActor func testPresentasiIzinBluetoothDitolak() { run(.bluetoothDenied) }
    @MainActor func testPresentasiDitolak() { run(.presentationDenied) }
    @MainActor func testBantuan() { run(.help) }
    @MainActor func testTambahPilihCara() { run(.add) }
    @MainActor func testTambahKodeGalat() { run(.addCode) }
    @MainActor func testTambahKonfirmasiGedung() { run(.addConfirm) }
    @MainActor func testTambahTautanUndangan() { run(.addInvitation) }
    @MainActor func testTambahBerhasil() { run(.addDone) }
    @MainActor func testTambahMenunggu() { run(.addPending) }
    @MainActor func testTambahGagal() { run(.addFailed) }

    /// Review Focus 1: cek target sentuh tidak lulus kosong bila tidak ada elemen konten yang diperiksa.
    @MainActor func testCekTargetSentuhGagalTanpaElemen() {
        guard let app = AccessibilityAudit.open(.add, variant: AuditVariant()) else { return }
        XCTExpectFailure("semua elemen difilter keluar: cek harus gagal") {
            AccessibilityAudit.checkTouchTargets(app, context: "tanpa elemen", requireTargets: true, excluding: { _ in true })
        }
        app.terminate()
    }
}

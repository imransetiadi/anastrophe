import XCTest

/// Audit setiap keadaan layar pada ukuran teks AX5 dalam bahasa ID dan EN, mode terang (TC-UX-02; ADR-0057).
final class AuditAX5Tests: XCTestCase {
    /// Di AX5 hampir setiap layar bisa digulir; batas halaman yang sama untuk semua keadaan.
    static let pages = 4

    override func setUp() async throws {
        continueAfterFailure = true
        await MainActor.run { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    private func run(_ screen: AuditScreen, file: StaticString = #filePath, line: UInt = #line) {
        for english in [false, true] {
            let variant = AuditVariant(largeText: true, english: english)
            guard let app = AccessibilityAudit.open(screen, variant: variant, file: file, line: line) else { continue }
            AccessibilityAudit.auditPages(app, screen: screen, context: "\(screen) \(variant)", pages: Self.pages, file: file, line: line)
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
}

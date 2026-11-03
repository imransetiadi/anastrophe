import XCTest

/// Audit setiap keadaan layar pada ukuran teks AX5 dalam bahasa ID dan EN, mode terang (TC-UX-02; ADR-0057).
final class AuditAX5Tests: XCTestCase {
    /// Di AX5 hampir setiap layar bisa digulir. Batas halaman cukup besar agar layar terpanjang (Bantuan) habis diaudit
    /// dengan gulir 60 % tinggi kontainer; layar pendek berhenti sendiri saat isi tidak lagi bergerak, dan test gagal
    /// bila batas habis sebelum ujung isi.
    static let pages = 24

    override func setUp() async throws {
        continueAfterFailure = true
        await MainActor.run { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    private func run(_ screen: AuditScreen, file: StaticString = #filePath, line: UInt = #line) {
        for english in [false, true] {
            let variant = AuditVariant(largeText: true, english: english)
            guard let opened = AccessibilityAudit.open(screen, variant: variant, file: file, line: line) else { continue }
            if AccessibilityAudit.verifyAppearance(opened.app, expected: .light, context: "\(screen) \(variant)", file: file, line: line) {
                AccessibilityAudit.auditPages(opened, screen: screen, context: "\(screen) \(variant)", pages: Self.pages, largeText: true, file: file, line: line)
            }
            opened.app.terminate()
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

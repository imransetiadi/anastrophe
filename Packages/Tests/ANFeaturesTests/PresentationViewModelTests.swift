import ANCore
import Foundation
import Testing
@testable import ANFeatures

func stream(_ events: [PresentmentEvent]) -> AsyncStream<PresentmentEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: PresentmentEvent.self)
    events.forEach { continuation.yield($0) }
    continuation.finish()
    return stream
}

func card(status: CardStatus, credentials: [ChannelKind: Data] = [.ble: Data(repeating: 1, count: 16)]) -> Card {
    Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: ["Lobi"], status: status, credentials: credentials, notAfter: nil)
}

@MainActor
@Suite("Model presentasi & kelayakan kartu")
struct PresentationViewModelTests {
    @Test func urutanEventMenjadiFase() async {
        let model = PresentationViewModel(events: stream([.waitingForReader, .exchanging, .granted]))
        await model.start()
        #expect(model.phase == .granted)
        #expect(model.isFinished)
    }

    @Test func cooldownDanAlasanPenolakan() async {
        #expect(PresentationViewModel.phase(for: .coolingDown(seconds: 15)) == .coolingDown(seconds: 15))
        #expect(PresentationViewModel.phase(for: .readerFound(name: nil)) == .readerFound)

        let denied = PresentationViewModel(events: stream([.waitingForReader, .readerFound(name: nil), .denied(reason: .zoneNotAllowed)]))
        await denied.start()
        #expect(denied.phase == .denied(.zoneNotAllowed))
    }

    @Test func aliranBerakhirTanpaHasilDianggapBatal() async {
        let model = PresentationViewModel(events: stream([.waitingForReader]))
        await model.start()
        #expect(model.phase == .cancelled)
    }

    @Test func kartuPerluDipindahkanTidakBisaDipresentasikan() {
        let presentability = Presentability.evaluate(card(status: .needsTransfer), availability: [.ble: .available])
        #expect(presentability == .unavailable(.needsTransfer))
        #expect(!presentability.canPresent)
    }

    @Test func kartuAktifMemakaiKanalTerbaikYangTersedia() {
        let both = card(status: .active, credentials: [.ble: Data([1]), .nfcHCE: Data([2])])
        #expect(Presentability.evaluate(both, availability: [.ble: .available, .nfcHCE: .available]) == .available(.nfcHCE))
        #expect(Presentability.evaluate(both, availability: [.ble: .available, .nfcHCE: .notEligible]) == .available(.ble))
        #expect(Presentability.evaluate(both, availability: [.ble: .bluetoothOff, .nfcHCE: .regionBlocked]) == .unavailable(.bluetoothOff))
        #expect(Presentability.evaluate(both, availability: [.ble: .regionBlocked, .nfcHCE: .regionBlocked]) == .unavailable(.noChannel))
    }

    @Test(arguments: [(CardStatus.suspended, Presentability.Reason.suspended), (.revoked, .revoked), (.pendingApproval, .pendingApproval)])
    func statusTidakAktifDitolak(status: CardStatus, reason: Presentability.Reason) {
        #expect(Presentability.evaluate(card(status: status), availability: [.ble: .available]) == .unavailable(reason))
    }

    @Test func bluetoothMatiAtauDitolakMemberiAlasanSpesifik() {
        // Temuan review I2: bukan "belum tersedia di wilayah Anda".
        let bleOnly = card(status: .active)
        #expect(Presentability.evaluate(bleOnly, availability: [.ble: .bluetoothOff]) == .unavailable(.bluetoothOff))
        #expect(Presentability.evaluate(bleOnly, availability: [.ble: .bluetoothUnauthorized]) == .unavailable(.bluetoothUnauthorized))
        let hceOnly = card(status: .active, credentials: [.nfcHCE: Data([2])])
        #expect(Presentability.evaluate(hceOnly, availability: [.nfcHCE: .entitlementMissing]) == .unavailable(.noChannel))
    }

    @Test func sertifikatKedaluwarsaTidakBisaDipresentasikan() {
        // Temuan review I5.
        var expired = card(status: .active)
        expired.notAfter = Date(timeIntervalSince1970: 1_000)
        #expect(Presentability.evaluate(expired, availability: [.ble: .available], now: Date(timeIntervalSince1970: 2_000)) == .unavailable(.expired))
        #expect(Presentability.evaluate(expired, availability: [.ble: .available], now: Date(timeIntervalSince1970: 500)) == .available(.ble))
    }

    @Test func kedaluwarsaYangBisaDiperpanjangTetapBisaDipakai() {
        // ADR-0023, TC-DEV-11: kartu kedaluwarsa tetap bisa di-tap; perpanjangan berjalan setelah
        // autentikasi, dan tap gagal tertutup bila perpanjangan gagal (mis. offline).
        var expired = card(status: .active)
        expired.notAfter = Date(timeIntervalSince1970: 1_000)
        #expect(Presentability.evaluate(expired, availability: [.ble: .available], renewable: true, now: Date(timeIntervalSince1970: 2_000)) == .available(.ble))
    }

    @Test(arguments: [
        (23.0, CardStatus.active, CardStatus.needsRenewal),
        (25.0, .active, .active),
        (-1.0, .active, .needsRenewal),
        (1.0, .suspended, .suspended),
    ])
    func statusTampilanPerluDiperbarui(hoursLeft: Double, stored: CardStatus, shown: CardStatus) {
        // FR-38, TC-DEV-10: sisa < 24 jam atau sudah lewat → "Perlu diperbarui".
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        var subject = card(status: stored)
        subject.notAfter = now.addingTimeInterval(hoursLeft * 3_600)
        #expect(subject.displayStatus(now: now) == shown)
    }

    @Test func readerDiLuarJangkauanMenjadiFaseAkhir() async {
        let model = PresentationViewModel(events: stream([.waitingForReader, .readerOutOfRange]))
        await model.start()
        #expect(model.phase == .readerOutOfRange)
        #expect(model.isFinished)
    }

    @Test func kanalTidakTersediaMenjadiFaseAkhir() async {
        let model = PresentationViewModel(events: stream([.waitingForReader, .unavailable(.bluetoothOff)]))
        await model.start()
        #expect(model.phase == .unavailable(.bluetoothOff))
        #expect(model.isFinished)
    }

    @Test func perluDiperbaruiMasihBisaDipakai() {
        #expect(Presentability.evaluate(card(status: .needsRenewal), availability: [.ble: .available]) == .available(.ble))
    }
}

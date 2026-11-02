#if DEBUG
import ANCore
import ANNFCEnroll
import Foundation
import Testing
@testable import ANFeatures

/// Layar demo DEBUG untuk audit aksesibilitas dan verifikasi visual (`-ANDemoScreen`, ADR-0057).
@Suite("Layar demo (DEBUG)")
struct DemoScreenTests {
    @Test(arguments: [
        ("presentation", nil), ("bluetooth-denied", nil), ("presentation-denied", nil), ("add", nil), ("add-done", nil),
        ("empty", nil), ("detail-suspended", nil), ("xyz", nil), (nil, nil),
        ("detail", DemoScreen.detail), ("lab", .lab), ("help", .help),
    ] as [(String?, DemoScreen?)])
    func layarLiveTanpaPresentasi(raw: String?, expected: DemoScreen?) {
        // Dengan layanan live, layar yang memulai presentasi tidak pernah dibuka otomatis (CLAUDE.md aturan 4).
        #expect(DemoScreen.live(raw) == expected)
    }

    @MainActor
    @Test func nilaiTakDikenalDiabaikan() async throws {
        let services = await AppServices.demo(screen: "xyz")
        #expect(services.demoScreen == nil)
        #expect(try await services.cards.all().count == 4)
    }

    @MainActor
    @Test func demoKosongTanpaKartu() async throws {
        #expect(try await AppServices.demo(screen: "empty").cards.all().isEmpty)
        #expect(try await AppServices.demo(screen: nil).cards.all().count == 4)
    }

    @MainActor
    @Test func demoTambahKartuLayananTersedia() async {
        let addScreens = DemoScreen.allCases.filter(\.opensAddCard)
        #expect(Set(addScreens.map(\.rawValue)) == ["add", "add-code", "add-confirm", "add-invitation", "add-done", "add-pending", "add-failed"])
        for screen in addScreens {
            // TLD cadangan RFC 2606: layanan tampak tersedia tanpa pernah tersambung.
            #expect(await AppServices.demo(screen: screen.rawValue).apiBaseURL == URL(string: "https://demo.invalid"), "\(screen)")
        }
        #expect(await AppServices.demo(screen: nil).apiBaseURL == nil)
        #expect(await AppServices.demo(screen: "help").apiBaseURL == nil)
    }

    @MainActor
    @Test(arguments: [
        ("presentation-denied", [PresentmentEvent.waitingForReader, .denied(reason: .zoneNotAllowed)]),
        ("bluetooth-denied", [.waitingForReader, .unavailable(.bluetoothUnauthorized)]),
        ("presentation", [.waitingForReader]),
    ])
    func demoPresentasiMengikutiLayar(raw: String, expected: [PresentmentEvent]) async throws {
        let services = await AppServices.demo(screen: raw)
        let card = try #require(try await services.cards.all().first)
        let stream = await services.launcher.start(card: card, channel: .ble)
        // Naskah demo dikirim seketika lalu aliran tetap terbuka; batas waktu membuat event yang kurang gagal,
        // bukan menggantung.
        let collector = Task {
            var events: [PresentmentEvent] = []
            for await event in stream {
                events.append(event)
                if events.count == expected.count { break }
            }
            return events
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(2))
            collector.cancel()
        }
        let events = await collector.value
        deadline.cancel()
        #expect(events == expected)
    }

    @MainActor
    @Test(arguments: [DemoScreen.add, .addCode, .addConfirm, .addInvitation, .addDone, .addPending, .addFailed])
    func langkahDemoTambahKartu(screen: DemoScreen) async {
        let model = AddCardModel(services: await AppServices.demo(screen: screen.rawValue), reader: FixedCardOwnershipReader(.failure(.cardReaderUnavailable)))
        await AddCardDemo.apply(screen, to: model)
        switch (screen, model.step) {
        case (.add, .chooseMethod):
            #expect(model.fieldError == nil)
        case (.addCode, .siteCode):
            #expect(model.fieldError == localized("add.code.invalid"))
        case (.addConfirm, .confirmSite(let site)):
            #expect(site.name == "Menara Anastrophe")
        case (.addInvitation, .invitation):
            #expect(model.fieldError == localized("add.link.invalid"))
        case (.addDone, .done(let card)):
            #expect(card.siteName == "Menara Anastrophe")
        case (.addPending, .pending(let siteName)):
            #expect(siteName == "Menara Anastrophe")
        case (.addFailed, .failed(let failure)):
            #expect(failure.offersInvitation)
        default:
            Issue.record("\(screen): langkah \(model.step)")
        }
    }
}
#endif

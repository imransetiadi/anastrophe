import ANCore
import Foundation
import SwiftUI
import Testing
@testable import ANFeatures

@MainActor
final class SpyLauncher: PresentationLaunching {
    private(set) var starts = 0
    private(set) var cancels = 0

    func start(card: Card, channel: ChannelKind) async -> AsyncStream<PresentmentEvent> {
        starts += 1
        await Task.yield()
        return AsyncStream { $0.yield(.waitingForReader) }
    }

    func cancel() async { cancels += 1 }
}

@MainActor
func services(launcher: SpyLauncher) -> AppServices {
    let base = AppServices.inMemory()
    return AppServices(cards: base.cards, keys: base.keys, records: base.records, availability: { [:] }, launcher: launcher, foreground: ForegroundState(), authenticator: ImmediateAuthenticator())
}

@MainActor
@Suite("Siklus hidup presentasi (temuan review C1, I1)")
struct LifecycleTests {
    @Test func inactiveTidakMembatalkanPresentasi() async {
        // Face ID/passcode membuat scene `.inactive`; itu bukan meninggalkan foreground.
        let launcher = SpyLauncher()
        let app = services(launcher: launcher)
        await app.handleScenePhase(.inactive)
        #expect(launcher.cancels == 0)
        #expect(app.foreground.isActive)
    }

    @Test func backgroundMembatalkanPresentasi() async {
        let launcher = SpyLauncher()
        let app = services(launcher: launcher)
        await app.handleScenePhase(.background)
        #expect(launcher.cancels == 1)
        #expect(!app.foreground.isActive)
        await app.handleScenePhase(.active)
        #expect(app.foreground.isActive)
    }

    @Test func cobaLagiTidakMembatalkanPresentasiBaru() async {
        // SwiftUI memanggil onDismiss saat item lembar diganti (Coba lagi).
        let launcher = SpyLauncher()
        let controller = PresentationController(launcher: launcher)
        let card = card(status: .active)
        await controller.use(card, channel: .ble)
        await controller.use(card, channel: .ble)
        await controller.sheetDismissed()
        #expect(launcher.cancels == 0)
        #expect(controller.request != nil)

        controller.request = nil  // pengguna menutup lembar
        await controller.sheetDismissed()
        #expect(launcher.cancels == 1)
    }

    @Test func penyimpananGagalTerlihatDanTidakMempresentasikan() async {
        // Minor 10: bila store gagal dibuka, app memberi tahu dan tidak berpura-pura bekerja.
        let services = AppServices.storageUnavailable()
        #expect(services.storageFailed)
        var events = await services.launcher.start(card: card(status: .active), channel: .ble).makeAsyncIterator()
        #expect(await events.next() == .cancelled)
        #expect(await events.next() == nil)
    }

    @Test func ketukGandaHanyaMemulaiSatuPresentasi() async {
        let launcher = SpyLauncher()
        let controller = PresentationController(launcher: launcher)
        let card = card(status: .active)
        async let first: Void = controller.use(card, channel: .ble)
        async let second: Void = controller.use(card, channel: .ble)
        _ = await (first, second)
        #expect(launcher.starts == 1)
    }
}

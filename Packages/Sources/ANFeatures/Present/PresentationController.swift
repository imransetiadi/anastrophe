import ANCore
import Observation

/// Mengatur presentasi yang sedang tampil di lembar presentasi.
@MainActor
@Observable
final class PresentationController {
    var request: PresentationRequest?
    /// Mencegah ketuk ganda memulai dua presentasi.
    private(set) var isStarting = false
    private let launcher: any PresentationLaunching

    init(launcher: any PresentationLaunching) {
        self.launcher = launcher
    }

    func use(_ card: Card, channel: ChannelKind) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let events = await launcher.start(card: card, channel: channel)
        request = PresentationRequest(card: card, channel: channel, model: PresentationViewModel(events: events))
    }

    func cancel() async {
        await launcher.cancel()
    }

    /// Dipanggil oleh `onDismiss` lembar presentasi. SwiftUI juga memanggilnya saat item
    /// lembar diganti ("Coba lagi"), jadi batalkan hanya bila lembar benar-benar ditutup.
    func sheetDismissed() async {
        guard request == nil else { return }
        await launcher.cancel()
    }
}

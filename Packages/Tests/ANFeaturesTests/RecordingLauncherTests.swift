import ANCore
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@MainActor
@Suite("Pencatatan riwayat tap (FR-30)")
struct RecordingLauncherTests {
    let card = Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: [], status: .active, credentials: [.ble: Data(repeating: 1, count: 16)], notAfter: nil)
    let moment = Date(timeIntervalSince1970: 1_794_000_000)

    func run(_ events: [PresentmentEvent]) async throws -> [TapEntry] {
        let history = InMemoryTapHistoryStore()
        let moment = moment
        let launcher = RecordingLauncher(base: ScriptedPresentationLauncher(events: events, finishes: true), history: history, now: { moment })
        var stream = await launcher.start(card: card, channel: .ble).makeAsyncIterator()
        while await stream.next() != nil {}
        try await Task.sleep(for: .milliseconds(50))  // pencatatan berjalan setelah aliran selesai
        return try await history.entries(for: card.id, since: .distantPast)
    }

    @Test func diizinkanDicatat() async throws {
        let entries = try await run([.waitingForReader, .granted])
        #expect(entries == [TapEntry(id: entries.first?.id ?? UUID(), cardID: card.id, date: moment, channel: .ble, granted: true, denyReason: nil)])
    }

    @Test func ditolakDicatatDenganAlasan() async throws {
        let entries = try await run([.waitingForReader, .denied(reason: .expired)])
        #expect(entries.count == 1 && entries[0].granted == false && entries[0].denyReason == .expired)
    }

    @Test func batalTidakDicatat() async throws {
        // Review Focus 1: hanya transaksi dengan reader yang menjadi riwayat.
        #expect(try await run([.waitingForReader, .cancelled]).isEmpty)
        #expect(try await run([.waitingForReader, .readerOutOfRange]).isEmpty)
    }
}

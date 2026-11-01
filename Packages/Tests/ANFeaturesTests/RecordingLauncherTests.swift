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
        // Setiap entri disimpan sebelum event-nya diteruskan, jadi semua sudah ada saat aliran selesai.
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

    @Test(arguments: [PresentmentEvent.coolingDown(seconds: 5), .waitingForReader, .readerFound(name: "Lobi"), .exchanging, .timedOut, .cancelled, .unavailable(.bluetoothOff), .readerOutOfRange])
    func bukanTransaksiTidakDicatat(event: PresentmentEvent) {
        // M4: hanya hasil transaksi dengan reader yang menjadi riwayat.
        #expect(RecordingLauncher.entry(for: event, cardID: card.id, channel: .ble, at: moment) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func entriTersimpanSebelumHasilDiteruskan() async throws {
        // M7: sheet memuat ulang riwayat saat ditutup, jadi entri harus sudah ada ketika hasil tiba.
        let history = GatedAppendHistory()
        let moment = moment, card = card
        let launcher = RecordingLauncher(base: ScriptedPresentationLauncher(events: [.granted], finishes: true), history: history, now: { moment })
        let stream = await launcher.start(card: card, channel: .ble)
        let seenAtResult = Task { () -> Int? in
            for await event in stream where event == .granted {
                return try? await history.entries(for: card.id, since: .distantPast).count
            }
            return nil
        }
        var started = history.appendStarted.makeAsyncIterator()
        _ = await started.next()
        await history.open()
        #expect(await seenAtResult.value == 1)
    }
}

/// Store riwayat yang menahan `append` sampai dibuka, untuk menguji urutan simpan lalu teruskan.
actor GatedAppendHistory: TapHistoryStore {
    let appendStarted: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var waiter: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private var items: [TapEntry] = []

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        appendStarted = stream
        signal = continuation
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func append(_ entry: TapEntry) async throws {
        signal.yield()
        if !isOpen { await withCheckedContinuation { waiter = $0 } }
        items.append(entry)
    }

    func entries(for cardID: UUID, since: Date) async throws -> [TapEntry] { items.filter { $0.cardID == cardID } }
    func purge(before: Date) async throws {}
    func removeAll(for cardID: UUID) async throws {}
    func removeAll(except cardIDs: Set<UUID>) async throws {}
}


import ANCore
import Foundation
import SwiftData
import Testing
@testable import ANStorage

@Suite("Riwayat tap lokal (FR-30, SDD §5.3)")
struct TapHistoryStoreTests {
    func store() throws -> SwiftDataTapHistoryStore {
        try SwiftDataTapHistoryStore(directory: FileManager.default.temporaryDirectory.appending(path: "anastrophe-tap-\(UUID().uuidString)"))
    }

    @Test func entriTerbaruDuluDanPerKartu() async throws {
        let history = try store()
        let card = UUID(), other = UUID()
        try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 1_000), channel: .ble, granted: true, denyReason: nil))
        try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 2_000), channel: .ble, granted: false, denyReason: .expired))
        try await history.append(TapEntry(cardID: other, date: Date(timeIntervalSince1970: 3_000), channel: .ble, granted: true, denyReason: nil))
        let entries = try await history.entries(for: card, since: Date(timeIntervalSince1970: 0))
        #expect(entries.map(\.date) == [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
        #expect(entries.first?.denyReason == .expired)
    }

    @Test func pangkasDanHapusPerKartu() async throws {
        let history = try store()
        let card = UUID(), other = UUID()
        try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 1_000), channel: .ble, granted: true, denyReason: nil))
        try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 5_000), channel: .ble, granted: true, denyReason: nil))
        try await history.append(TapEntry(cardID: other, date: Date(timeIntervalSince1970: 5_000), channel: .ble, granted: true, denyReason: nil))
        try await history.purge(before: Date(timeIntervalSince1970: 2_000))
        #expect(try await history.entries(for: card, since: .distantPast).count == 1)
        try await history.removeAll(for: card)
        #expect(try await history.entries(for: card, since: .distantPast).isEmpty)
        #expect(try await history.entries(for: other, since: .distantPast).count == 1)  // kartu lain utuh
    }

    @Test(arguments: ["swiftdata", "memory"])
    func hapusYatimMenyisakanKartuYangAda(kind: String) async throws {
        // M1: entri kartu yang sudah tidak ada dibersihkan; kartu yang masih ada utuh.
        let history: any TapHistoryStore = kind == "memory" ? InMemoryTapHistoryStore() : try store()
        let a = UUID(), b = UUID(), orphan = UUID()
        for card in [a, b, orphan] {
            try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 1_000), channel: .ble, granted: true, denyReason: nil))
        }
        try await history.removeAll(except: [a, b])
        #expect(try await history.entries(for: orphan, since: .distantPast).isEmpty)
        #expect(try await history.entries(for: a, since: .distantPast).count == 1)
        #expect(try await history.entries(for: b, since: .distantPast).count == 1)
    }

    @Test func barisRusakDilewati() async throws {
        // M3: satu baris dari build lain (kanal tak dikenal) tidak menyembunyikan seluruh riwayat kartu.
        let directory = FileManager.default.temporaryDirectory.appending(path: "anastrophe-tap-\(UUID().uuidString)")
        let card = UUID()
        let good = TapEntry(cardID: card, date: Date(timeIntervalSince1970: 1_000), channel: .ble, granted: true, denyReason: nil)
        let bad = TapEntry(cardID: card, date: Date(timeIntervalSince1970: 2_000), channel: .ble, granted: true, denyReason: nil)
        do {
            let seeded = try SwiftDataTapHistoryStore(directory: directory)
            try await seeded.append(good)
            try await seeded.append(bad)
        }
        do {
            let configuration = ModelConfiguration(schema: Schema([TapEntity.self]), url: directory.appending(path: "taps.store"), cloudKitDatabase: .none)
            let context = ModelContext(try ModelContainer(for: TapEntity.self, configurations: configuration))
            let badID = bad.id
            try context.fetch(FetchDescriptor<TapEntity>(predicate: #Predicate { $0.id == badID })).first?.channel = "kanal-masa-depan"
            try context.save()
        }
        let reopened = try SwiftDataTapHistoryStore(directory: directory)
        #expect(try await reopened.entries(for: card, since: .distantPast) == [good])
    }
}

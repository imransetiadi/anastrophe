import ANCore
import Foundation
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
        let card = UUID()
        try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 1_000), channel: .ble, granted: true, denyReason: nil))
        try await history.append(TapEntry(cardID: card, date: Date(timeIntervalSince1970: 5_000), channel: .ble, granted: true, denyReason: nil))
        try await history.purge(before: Date(timeIntervalSince1970: 2_000))
        #expect(try await history.entries(for: card, since: .distantPast).count == 1)
        try await history.removeAll(for: card)
        #expect(try await history.entries(for: card, since: .distantPast).isEmpty)
    }
}

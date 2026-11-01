import ANCore
import CoreData
import Foundation
import Testing
import ANStorage

/// ADR-0029: riwayat tidak pernah membuat app gagal dibuka; store dibuat ulang hanya bila rusak
/// atau skemanya tak termigrasi, dan riwayat yang masih terbaca tidak dihapus.
@Suite("Pemulihan store riwayat (ADR-0029)")
struct TapHistoryRecoveryTests {
    func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "anastrophe-tap-\(UUID().uuidString)")
    }

    func entry(_ card: UUID) -> TapEntry {
        TapEntry(cardID: card, date: .now, channel: .ble, granted: true, denyReason: nil)
    }

    /// Store dengan entitas `TapEntity` berskema lama yang tidak bisa dimigrasi otomatis (satu baris berisi).
    func makeLegacyStore(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = NSAttributeDescription()
        legacy.name = "legacy"
        legacy.type = .integer64
        legacy.isOptional = false
        let entity = NSEntityDescription()
        entity.name = "TapEntity"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [legacy]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "TapEntity", into: context).setValue(1, forKey: "legacy")
            try context.save()
        }
        try coordinator.remove(store)
    }

    @Test func storeRusakDibuatUlangDanPersisten() async throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8_192).write(to: dir.appending(path: "taps.store"))
        let card = UUID()
        let history = SwiftDataTapHistoryStore.openRecovering(directory: dir)
        try await history.append(entry(card))
        let reopened = try SwiftDataTapHistoryStore(directory: dir)
        #expect(try await reopened.entries(for: card, since: .distantPast).count == 1)
    }

    @Test func skemaTakTermigrasiDibuatUlang() async throws {
        let dir = directory()
        try makeLegacyStore(at: dir.appending(path: "taps.store"))
        #expect(throws: (any Error).self) { try SwiftDataTapHistoryStore(directory: dir) }  // prasyarat: migrasi memang gagal
        let card = UUID()
        let history = SwiftDataTapHistoryStore.openRecovering(directory: dir)
        try await history.append(entry(card))
        let reopened = try SwiftDataTapHistoryStore(directory: dir)
        #expect(try await reopened.entries(for: card, since: .distantPast).count == 1)
    }

    @Test func storeTakTerbacaTidakDihapus() async throws {
        let dir = directory()
        let card = UUID()
        do {
            let seeded = try SwiftDataTapHistoryStore(directory: dir)
            try await seeded.append(entry(card))
        }
        let file = dir.appending(path: "taps.store").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file)
        let history = SwiftDataTapHistoryStore.openRecovering(directory: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
        #expect(history is InMemoryTapHistoryStore)
        let reopened = try SwiftDataTapHistoryStore(directory: dir)
        #expect(try await reopened.entries(for: card, since: .distantPast).count == 1)
    }

    @Test func storeSehatDipakaiApaAdanya() async throws {
        let dir = directory()
        let card = UUID()
        do {
            let seeded = try SwiftDataTapHistoryStore(directory: dir)
            try await seeded.append(entry(card))
        }
        let history = SwiftDataTapHistoryStore.openRecovering(directory: dir)
        #expect(history is SwiftDataTapHistoryStore)
        #expect(try await history.entries(for: card, since: .distantPast).count == 1)
    }
}

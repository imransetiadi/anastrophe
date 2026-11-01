import ANCore
import CoreData
import Foundation
import SwiftData

/// Riwayat tap lokal 30 hari (FR-30, SDD §5.3); hanya di perangkat.
public protocol TapHistoryStore: Sendable {
    func append(_ entry: TapEntry) async throws
    /// Terbaru dulu.
    func entries(for cardID: UUID, since: Date) async throws -> [TapEntry]
    func purge(before: Date) async throws
    func removeAll(for cardID: UUID) async throws
}

@Model
final class TapEntity {
    @Attribute(.unique) var id: UUID
    var cardID: UUID
    var date: Date
    var channel: String
    var granted: Bool
    var denyReason: String?

    init(_ entry: TapEntry) {
        id = entry.id
        cardID = entry.cardID
        date = entry.date
        channel = entry.channel.rawValue
        granted = entry.granted
        denyReason = entry.denyReason?.rawValue
    }

    func entry() throws -> TapEntry {
        guard let channel = ChannelKind(rawValue: channel) else { throw ANError.invalidData }
        return TapEntry(id: id, cardID: cardID, date: date, channel: channel, granted: granted, denyReason: denyReason.flatMap(DenyReason.init(rawValue:)))
    }
}

/// Riwayat di SwiftData terpisah; direktori memakai file protection `.complete` dan dikecualikan
/// dari backup, sama seperti metadata kartu (SDD §5.3).
public actor SwiftDataTapHistoryStore: TapHistoryStore {
    static let storeFileName = "taps.store"
    private let context: ModelContext

    public init(directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directory = directory
        try directory.setResourceValues(excluded)
        let configuration = ModelConfiguration(schema: Schema([TapEntity.self]), url: directory.appending(path: Self.storeFileName), cloudKitDatabase: .none)
        context = ModelContext(try ModelContainer(for: TapEntity.self, configurations: configuration))
    }

    public func append(_ entry: TapEntry) async throws {
        context.insert(TapEntity(entry))
        try context.save()
    }

    public func entries(for cardID: UUID, since: Date) async throws -> [TapEntry] {
        let descriptor = FetchDescriptor<TapEntity>(predicate: #Predicate { $0.cardID == cardID && $0.date >= since }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try context.fetch(descriptor).map { try $0.entry() }
    }

    public func purge(before: Date) async throws {
        try context.delete(model: TapEntity.self, where: #Predicate { $0.date < before })
        try context.save()
    }

    public func removeAll(for cardID: UUID) async throws {
        try context.delete(model: TapEntity.self, where: #Predicate { $0.cardID == cardID })
        try context.save()
    }
}

extension SwiftDataTapHistoryStore {
    /// Membuka riwayat tanpa pernah gagal (ADR-0029), agar kartu tidak ikut tak tersedia. `directory`
    /// khusus riwayat: store yang rusak atau skemanya tak termigrasi dihapus lalu dibuat ulang sekali;
    /// galat lain memakai riwayat sementara di memori tanpa menghapus apa pun.
    public static func openRecovering(directory: URL) -> any TapHistoryStore {
        if let store = try? SwiftDataTapHistoryStore(directory: directory) { return store }
        if isUnusable(store: directory.appending(path: storeFileName)) {
            try? FileManager.default.removeItem(at: directory)
            if let store = try? SwiftDataTapHistoryStore(directory: directory) { return store }
        }
        return InMemoryTapHistoryStore()
    }

    /// Berkas bukan database, atau skemanya tidak cocok dengan model saat ini. `SwiftDataError` tidak
    /// mengungkap galat di dalamnya, jadi metadata store dibaca lewat Core Data. Berkas yang tidak bisa
    /// dibaca (proteksi data, izin) atau tidak ada tidak dihitung rusak.
    static func isUnusable(store url: URL) -> Bool {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [TapEntity.self]) else { return false }
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
            return !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        } catch let error as CocoaError where error.code == .fileReadCorruptFile {
            return true
        } catch {
            return false
        }
    }
}

/// Riwayat sementara untuk preview, demo, dan penyimpanan cadangan.
public actor InMemoryTapHistoryStore: TapHistoryStore {
    private var items: [TapEntry] = []

    public init() {}

    public func append(_ entry: TapEntry) async throws { items.append(entry) }

    public func entries(for cardID: UUID, since: Date) async throws -> [TapEntry] {
        items.filter { $0.cardID == cardID && $0.date >= since }.sorted { $0.date > $1.date }
    }

    public func purge(before: Date) async throws { items.removeAll { $0.date < before } }

    public func removeAll(for cardID: UUID) async throws { items.removeAll { $0.cardID == cardID } }
}

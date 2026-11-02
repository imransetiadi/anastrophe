import ANCore
import Foundation
import SwiftData

@Model
final class CardEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var siteName: String
    var zones: [String]
    var statusRaw: String
    /// `[ChannelKind: Data]` dalam JSON.
    var credentialsJSON: Data
    var notAfter: Date?
    var createdAt: Date

    init(_ card: Card, createdAt: Date) throws {
        id = card.id
        name = card.name
        siteName = card.siteName
        zones = card.zones
        statusRaw = card.status.rawValue
        credentialsJSON = try JSONEncoder().encode(card.credentials)
        notAfter = card.notAfter
        self.createdAt = createdAt
    }

    func apply(_ card: Card) throws {
        name = card.name
        siteName = card.siteName
        zones = card.zones
        statusRaw = card.status.rawValue
        credentialsJSON = try JSONEncoder().encode(card.credentials)
        notAfter = card.notAfter
    }

    func card() throws -> Card {
        guard let status = CardStatus(rawValue: statusRaw) else { throw ANError.invalidData }
        return Card(
            id: id,
            name: name,
            siteName: siteName,
            zones: zones,
            status: status,
            credentials: try JSONDecoder().decode([ChannelKind: Data].self, from: credentialsJSON),
            notAfter: notAfter
        )
    }
}

/// Metadata kartu di SwiftData. Direktori store memakai file protection
/// `.complete` dan dikecualikan dari backup (SDD §5.3).
public actor SwiftDataCardStore: CardStore {
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

        let configuration = ModelConfiguration(
            schema: Schema([CardEntity.self]),
            url: directory.appending(path: "cards.store"),
            cloudKitDatabase: .none
        )
        context = ModelContext(try ModelContainer(for: CardEntity.self, configurations: configuration))
    }

    public func all() async throws -> [Card] {
        try context.fetch(FetchDescriptor<CardEntity>(sortBy: [SortDescriptor(\.createdAt)])).map { try $0.card() }
    }

    public func add(_ card: Card) async throws {
        try CardLimit.ensureCanAdd(currentCount: try context.fetchCount(FetchDescriptor<CardEntity>()))
        context.insert(try CardEntity(card, createdAt: .now))
        try context.save()
    }

    public func update(_ card: Card) async throws {
        try entity(id: card.id).apply(card)
        try context.save()
    }

    public func remove(id: UUID) async throws {
        context.delete(try entity(id: id))
        try context.save()
    }

    /// Atomik di dalam actor: baca, ubah, dan simpan tanpa celah bagi penulis lain.
    public func update(id: UUID, _ mutate: @Sendable (inout Card) -> Bool) async throws -> Bool {
        let entity = try entity(id: id)
        var card = try entity.card()
        guard mutate(&card) else { return false }
        try entity.apply(card)
        try context.save()
        return true
    }

    private func entity(id: UUID) throws -> CardEntity {
        var descriptor = FetchDescriptor<CardEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else { throw ANError.invalidData }
        return entity
    }
}

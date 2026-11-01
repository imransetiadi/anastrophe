import ANCore
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@MainActor
@Suite("Daftar kartu: kartu kedaluwarsa (ADR-0023, TC-DEV-11)")
struct KeysViewModelTests {
    let credentialID = Data(repeating: 0x5E, count: 16)
    let expiredAt = Date(timeIntervalSince1970: 1_000)

    func expiredCard(in services: AppServices, renewalURL: URL?) async throws -> Card {
        _ = try services.keys.createKey(for: credentialID)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: expiredAt, groupKeys: [:], renewalURL: renewalURL))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: expiredAt)
        try await services.cards.add(card)
        return card
    }

    @Test func kartuKedaluwarsaDariBackendBisaDipakai() async throws {
        // Tanpa ini tombol "Gunakan kartu" nonaktif dan perpanjangan saat tap tidak pernah terjadi.
        let services = AppServices.inMemory()
        let card = try await expiredCard(in: services, renewalURL: URL(string: "http://127.0.0.1:8080"))
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.presentability(of: card) == .available(.ble))
    }

    @Test func kartuKedaluwarsaTanpaBackendTetapDitolak() async throws {
        // Kartu lab_ca.py tidak bisa diperpanjang, jadi tap pasti gagal: tetap nonaktif.
        let services = AppServices.inMemory()
        let card = try await expiredCard(in: services, renewalURL: nil)
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.presentability(of: card) == .unavailable(.expired))
    }

    @Test func masaBerlakuKartuMengikutiRecord() async throws {
        // Review I1: record adalah sumber kebenaran masa berlaku; kartu di daftar disesuaikan.
        let services = AppServices.inMemory()
        let renewedUntil = Date(timeIntervalSince1970: 1_794_787_200)
        _ = try services.keys.createKey(for: credentialID)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: renewedUntil, groupKeys: [:], renewalURL: URL(string: "http://127.0.0.1:8080")))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: expiredAt)
        try await services.cards.add(card)
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.cards.first?.notAfter == renewedUntil)
        #expect(try await services.cards.all().first?.notAfter == renewedUntil)
    }

    func nearExpiryModel(online: Bool, hoursLeft: Double) async throws -> (KeysViewModel, Card) {
        let services = AppServices.inMemory(events: [.waitingForReader], connectivity: FixedConnectivity(isOnline: online))
        _ = try services.keys.createKey(for: credentialID)
        let notAfter = Date.now.addingTimeInterval(hoursLeft * 3_600)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: notAfter, groupKeys: [:], renewalURL: URL(string: "http://127.0.0.1:8080")))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: notAfter)
        try await services.cards.add(card)
        let model = KeysViewModel(services: services)
        await model.load()
        return (model, card)
    }

    @Test func peringatanOfflineSaatPerluDiperbarui() async throws {
        // TC-DEV-10: sisa < 24 jam dan offline → "Perlu terhubung ke internet".
        let (offline, card) = try await nearExpiryModel(online: false, hoursLeft: 12)
        #expect(offline.renewalNotice(for: card) == .needsInternet)
        let (online, sameCard) = try await nearExpiryModel(online: true, hoursLeft: 12)
        #expect(online.renewalNotice(for: sameCard) == .renewsOnNextUse)
    }

    @Test func tanpaPeringatanBilaMasihLama() async throws {
        let (model, card) = try await nearExpiryModel(online: false, hoursLeft: 5 * 24)
        #expect(model.renewalNotice(for: card) == nil)
    }

    @Test func riwayatLebihDariTigaPuluhHariDipangkas() async throws {
        // Review Focus 3 (FR-30): hanya 30 hari terakhir yang tampil dan disimpan.
        let services = AppServices.inMemory()
        let card = Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await services.cards.add(card)
        try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now.addingTimeInterval(-31 * 86_400), channel: .ble, granted: true, denyReason: nil))
        try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now.addingTimeInterval(-86_400), channel: .ble, granted: false, denyReason: .suspended))
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.history(for: card).count == 1)
        #expect(try await services.tapHistory.entries(for: card.id, since: .distantPast).count == 1)
    }

    @Test func riwayatLebihDariDuaPuluhTetapDimuatSemua() async throws {
        // ADR-0030: semua tap 30 hari bisa dibuka lewat "Lihat semua", jadi view model tidak memotong.
        let services = AppServices.inMemory()
        let card = Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await services.cards.add(card)
        for hour in 1...25 {
            try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now.addingTimeInterval(Double(-hour * 3_600)), channel: .ble, granted: true, denyReason: nil))
        }
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.history(for: card).count == 25)
    }

    @Test func daftarTampilSebelumRiwayatSelesai() async throws {
        // M2: daftar kartu tidak menunggu riwayat (NFR-P03); riwayat menyusul.
        let base = AppServices.inMemory()
        let card = Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await base.cards.add(card)
        let history = GatedTapHistoryStore()
        let services = AppServices(cards: base.cards, keys: base.keys, records: base.records, availability: { [:] }, launcher: SpyLauncher(), foreground: ForegroundState(), authenticator: ImmediateAuthenticator(), tapHistory: history)
        let model = KeysViewModel(services: services)
        let loading = Task { await model.load() }
        var requests = history.requested.makeAsyncIterator()
        _ = await requests.next()
        #expect(!model.isLoading)
        #expect(model.cards.map(\.id) == [card.id])
        await history.open()
        await loading.value
    }

    @Test func riwayatYatimDibersihkanSaatMuat() async throws {
        // M1: riwayat kartu yang sudah tidak ada (hapus terputus) dibersihkan saat daftar dimuat.
        let services = AppServices.inMemory()
        let card = Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await services.cards.add(card)
        let orphan = UUID()
        try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now.addingTimeInterval(-60), channel: .ble, granted: true, denyReason: nil))
        try await services.tapHistory.append(TapEntry(cardID: orphan, date: .now.addingTimeInterval(-60), channel: .ble, granted: true, denyReason: nil))
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(try await services.tapHistory.entries(for: orphan, since: .distantPast).isEmpty)
        #expect(try await services.tapHistory.entries(for: card.id, since: .distantPast).count == 1)
    }

    @Test func gagalMuatKartuTidakMenghapusRiwayat() async throws {
        // Review Focus 1: daftar kosong karena galat bukan berarti semua kartu sudah dihapus.
        let base = AppServices.inMemory()
        let history = InMemoryTapHistoryStore()
        let card = UUID()
        try await history.append(TapEntry(cardID: card, date: .now.addingTimeInterval(-60), channel: .ble, granted: true, denyReason: nil))
        let services = AppServices(cards: FailingCardStore(), keys: base.keys, records: base.records, availability: { [:] }, launcher: SpyLauncher(), foreground: ForegroundState(), authenticator: ImmediateAuthenticator(), tapHistory: history)
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(try await history.entries(for: card, since: .distantPast).count == 1)
    }
}

/// Store riwayat yang menahan `entries(for:since:)` sampai dibuka, untuk menguji urutan muat.
actor GatedTapHistoryStore: TapHistoryStore {
    let requested: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        requested = stream
        signal = continuation
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func append(_ entry: TapEntry) async throws {}

    func entries(for cardID: UUID, since: Date) async throws -> [TapEntry] {
        signal.yield()
        if !isOpen { await withCheckedContinuation { waiters.append($0) } }
        return []
    }

    func purge(before: Date) async throws {}
    func removeAll(for cardID: UUID) async throws {}
    func removeAll(except cardIDs: Set<UUID>) async throws {}
}

/// Store kartu yang selalu gagal dibaca.
struct FailingCardStore: CardStore {
    func all() async throws -> [Card] { throw ANError.internalError }
    func add(_ card: Card) async throws { throw ANError.internalError }
    func update(_ card: Card) async throws { throw ANError.internalError }
    func remove(id: UUID) async throws { throw ANError.internalError }
}

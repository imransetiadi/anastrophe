import ANCore
import ANNetworking
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@MainActor
@Suite("Status kartu dari server (FR-38, ADR-0037)")
struct CardStatusRefresherTests {
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
    let tokens = KeychainStatusTokenStore(store: InMemorySecretStore())
    let credentialID = Data(repeating: 0x5E, count: 16)
    let serverCardID = "6f1c2a9e-0000-4000-8000-000000000001"
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    /// Kartu dengan record dari backend dan, bila diminta, token baca status.
    func setUp(status: CardStatus, withToken: Bool = true) async throws -> (Card, SwiftDataCardStore) {
        try records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: t0.addingTimeInterval(86_400), groupKeys: [:],
                                          renewalURL: URL(string: "http://127.0.0.1:8080"), serverCardID: serverCardID))
        if withToken { try tokens.save(Data(repeating: 0x31, count: 32), forCard: serverCardID) }
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: status, credentials: [.ble: credentialID], notAfter: nil)
        try await cards.add(card)
        return (card, cards)
    }

    func reply(_ status: String) -> (status: Int, body: String, contentType: String) {
        (200, #"{"status":"\#(status)"}"#, "application/json")
    }

    func refresher(_ cards: any CardStore, uptime: @escaping @Sendable () -> TimeInterval = { 0 }) -> CardStatusRefresher {
        CardStatusRefresher(cards: cards, records: records, tokens: tokens, uptime: uptime)
    }

    @Test func statusServerMenangguhkanKartu() async throws {
        let (_, cards) = try await setUp(status: .active)
        let transport = SequenceTransport([reply("SUSPENDED")])
        #expect(await refresher(cards).refresh(transport: transport))
        #expect(try await cards.all().first?.status == .suspended)
        #expect(transport.paths == ["/v1/cards/\(serverCardID)/status"])
    }

    @Test func statusServerMemulihkanKartu() async throws {
        let (_, cards) = try await setUp(status: .suspended)
        #expect(await refresher(cards).refresh(transport: SequenceTransport([reply("ACTIVE")])))
        #expect(try await cards.all().first?.status == .active)
    }

    @Test func statusServerMencabutKartu() async throws {
        let (_, cards) = try await setUp(status: .active)
        #expect(await refresher(cards).refresh(transport: SequenceTransport([reply("REVOKED")])))
        #expect(try await cards.all().first?.status == .revoked)
    }

    @Test func statusServerTidakMenimpaPerluDipindahkan() async throws {
        // Review Focus 5: kunci lokal hilang lebih menentukan daripada penangguhan di server.
        let (_, cards) = try await setUp(status: .needsTransfer)
        #expect(await !refresher(cards).refresh(transport: SequenceTransport([reply("SUSPENDED")])))
        #expect(try await cards.all().first?.status == .needsTransfer)
    }

    @Test func offlineMempertahankanStatus() async throws {
        // FR-25: tanpa jaringan status terakhir tetap dipakai.
        let (_, cards) = try await setUp(status: .suspended)
        #expect(await !refresher(cards).refresh(transport: SequenceTransport([])))
        #expect(try await cards.all().first?.status == .suspended)
        #expect(try tokens.token(forCard: serverCardID) != nil)  // galat jaringan bukan penolakan token
    }

    @Test func tokenDitolakServerDihapus() async throws {
        // Review akhir I1: token yang tidak lagi dikenali server dihapus lokal, sehingga perpanjangan
        // bertanda tangan berikutnya memasang token baru; status lokal tetap.
        let (_, cards) = try await setUp(status: .suspended)
        let transport = SequenceTransport([(404, #"{"type":"CARD-NOT-FOUND","status":404}"#, "application/problem+json")])
        #expect(await !refresher(cards).refresh(transport: transport))
        #expect(try await cards.all().first?.status == .suspended)
        #expect(try tokens.token(forCard: serverCardID) == nil)
    }

    @Test func refreshDibatasiSekaliPerMenit() async throws {
        let (_, cards) = try await setUp(status: .active)
        // Review akhir siklus hidup M6: batas frekuensi memakai jam monotonik, bukan jam dinding.
        let transport = SequenceTransport([reply("ACTIVE"), reply("ACTIVE")])
        let clock = UptimeClock()
        let refresher = refresher(cards, uptime: { clock.value })
        _ = await refresher.refresh(transport: transport)
        clock.value = 30
        _ = await refresher.refresh(transport: transport)
        #expect(transport.paths.count == 1)
        clock.value = 61
        _ = await refresher.refresh(transport: transport)
        #expect(transport.paths.count == 2)
    }

    @Test func kartuTanpaTokenDilewati() async throws {
        let (_, cards) = try await setUp(status: .active, withToken: false)
        let transport = SequenceTransport([reply("SUSPENDED")])
        #expect(await !refresher(cards).refresh(transport: transport))
        #expect(transport.paths.isEmpty)
    }

    @Test func appServicesMenyegarkanStatus() async throws {
        // Wiring: layanan memakai store kartu, record, dan token yang sama dengan provisioning.
        let services = AppServices.inMemory()
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: t0.addingTimeInterval(86_400), groupKeys: [:],
                                                   renewalURL: URL(string: "http://127.0.0.1:8080"), serverCardID: serverCardID))
        try services.statusTokens.save(Data(repeating: 0x31, count: 32), forCard: serverCardID)
        try await services.cards.add(Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: nil))
        #expect(await services.refreshCardStatuses(transport: SequenceTransport([reply("SUSPENDED")])))
        #expect(try await services.cards.all().first?.status == .suspended)
    }

    @Test func kartuDicabutTidakDiperiksa() async throws {
        // Review akhir siklus hidup M6: Dicabut bersifat final, jadi tidak ada permintaan lagi.
        let (_, cards) = try await setUp(status: .revoked)
        let transport = SequenceTransport([reply("ACTIVE")])
        #expect(await !refresher(cards).refresh(transport: transport))
        #expect(transport.paths.isEmpty)
    }

    @Test func penyegarTidakMenulisUlangSeluruhKartu() async throws {
        // Review akhir siklus hidup M4: status diubah lewat pembaruan terarah di dalam store, bukan
        // dengan menulis ulang salinan kartu yang bisa basi.
        let (_, base) = try await setUp(status: .active)
        let spy = FullWriteSpyCardStore(base: base)
        #expect(await refresher(spy).refresh(transport: SequenceTransport([reply("SUSPENDED")])))
        #expect(await spy.fullWrites == 0)
        #expect(try await base.all().first?.status == .suspended)
    }
}

/// Jam monotonik yang bisa diatur test.
final class UptimeClock: @unchecked Sendable {
    var value: TimeInterval = 0
}

/// Mencatat penulisan seluruh kartu (`update(_:)`); pembaruan terarah diteruskan ke store asli.
actor FullWriteSpyCardStore: CardStore {
    let base: SwiftDataCardStore
    private(set) var fullWrites = 0
    init(base: SwiftDataCardStore) { self.base = base }
    func all() async throws -> [Card] { try await base.all() }
    func add(_ card: Card) async throws { try await base.add(card) }
    func update(_ card: Card) async throws {
        fullWrites += 1
        try await base.update(card)
    }
    func remove(id: UUID) async throws { try await base.remove(id: id) }
    func update(id: UUID, _ mutate: @Sendable (inout Card) -> Bool) async throws -> Bool { try await base.update(id: id, mutate) }
}

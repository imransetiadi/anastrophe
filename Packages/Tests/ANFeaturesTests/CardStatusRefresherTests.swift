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

    func refresher(_ cards: SwiftDataCardStore) -> CardStatusRefresher {
        CardStatusRefresher(cards: cards, records: records, tokens: tokens)
    }

    @Test func statusServerMenangguhkanKartu() async throws {
        let (_, cards) = try await setUp(status: .active)
        let transport = SequenceTransport([reply("SUSPENDED")])
        #expect(await refresher(cards).refresh(now: t0, transport: transport))
        #expect(try await cards.all().first?.status == .suspended)
        #expect(transport.paths == ["/v1/cards/\(serverCardID)/status"])
    }

    @Test func statusServerMemulihkanKartu() async throws {
        let (_, cards) = try await setUp(status: .suspended)
        #expect(await refresher(cards).refresh(now: t0, transport: SequenceTransport([reply("ACTIVE")])))
        #expect(try await cards.all().first?.status == .active)
    }

    @Test func statusServerMencabutKartu() async throws {
        let (_, cards) = try await setUp(status: .active)
        #expect(await refresher(cards).refresh(now: t0, transport: SequenceTransport([reply("REVOKED")])))
        #expect(try await cards.all().first?.status == .revoked)
    }

    @Test func statusServerTidakMenimpaPerluDipindahkan() async throws {
        // Review Focus 5: kunci lokal hilang lebih menentukan daripada penangguhan di server.
        let (_, cards) = try await setUp(status: .needsTransfer)
        #expect(await !refresher(cards).refresh(now: t0, transport: SequenceTransport([reply("SUSPENDED")])))
        #expect(try await cards.all().first?.status == .needsTransfer)
    }

    @Test func offlineMempertahankanStatus() async throws {
        // FR-25: tanpa jaringan status terakhir tetap dipakai.
        let (_, cards) = try await setUp(status: .suspended)
        #expect(await !refresher(cards).refresh(now: t0, transport: SequenceTransport([])))
        #expect(try await cards.all().first?.status == .suspended)
        #expect(try tokens.token(forCard: serverCardID) != nil)  // galat jaringan bukan penolakan token
    }

    @Test func tokenDitolakServerDihapus() async throws {
        // Review akhir I1: token yang tidak lagi dikenali server dihapus lokal, sehingga perpanjangan
        // bertanda tangan berikutnya memasang token baru; status lokal tetap.
        let (_, cards) = try await setUp(status: .suspended)
        let transport = SequenceTransport([(404, #"{"type":"CARD-NOT-FOUND","status":404}"#, "application/problem+json")])
        #expect(await !refresher(cards).refresh(now: t0, transport: transport))
        #expect(try await cards.all().first?.status == .suspended)
        #expect(try tokens.token(forCard: serverCardID) == nil)
    }

    @Test func refreshDibatasiSekaliPerMenit() async throws {
        let (_, cards) = try await setUp(status: .active)
        let transport = SequenceTransport([reply("ACTIVE"), reply("ACTIVE")])
        let refresher = refresher(cards)
        _ = await refresher.refresh(now: t0, transport: transport)
        _ = await refresher.refresh(now: t0.addingTimeInterval(30), transport: transport)
        #expect(transport.paths.count == 1)
        _ = await refresher.refresh(now: t0.addingTimeInterval(61), transport: transport)
        #expect(transport.paths.count == 2)
    }

    @Test func kartuTanpaTokenDilewati() async throws {
        let (_, cards) = try await setUp(status: .active, withToken: false)
        let transport = SequenceTransport([reply("SUSPENDED")])
        #expect(await !refresher(cards).refresh(now: t0, transport: transport))
        #expect(transport.paths.isEmpty)
    }

    @Test func appServicesMenyegarkanStatus() async throws {
        // Wiring: layanan memakai store kartu, record, dan token yang sama dengan provisioning.
        let services = AppServices.inMemory()
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: t0.addingTimeInterval(86_400), groupKeys: [:],
                                                   renewalURL: URL(string: "http://127.0.0.1:8080"), serverCardID: serverCardID))
        try services.statusTokens.save(Data(repeating: 0x31, count: 32), forCard: serverCardID)
        try await services.cards.add(Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: nil))
        #expect(await services.refreshCardStatuses(now: t0, transport: SequenceTransport([reply("SUSPENDED")])))
        #expect(try await services.cards.all().first?.status == .suspended)
    }
}

import ANCore
import ANCrypto
import ANNetworking
import ANStorage
import ANTestSupport
import CryptoKit
import Foundation
import LocalAuthentication
import Testing
@testable import ANFeatures

/// Server yang tidak pernah menjawab sampai gate dibuka.
final class HangingTransport: HTTPTransport, @unchecked Sendable {
    let gate = AsyncGate()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await gate.wait()
        throw URLError(.timedOut)
    }
}

@MainActor
@Suite("Jadwal perpanjangan di sekitar tap (ADR-0023)")
struct RenewalSchedulerTests {
    let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
    let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
    let credentialID = Data(repeating: 0x5E, count: 16)
    let issued = Date(timeIntervalSince1970: 1_793_491_200)  // 2026-11-01
    var expires: Date { issued.addingTimeInterval(7 * 86_400) }
    let context = AuthorizedContext(laContext: LAContext())
    let renewReplies: [(status: Int, body: String, contentType: String)] = [
        (201, #"{"nonce":"\#(Data(repeating: 0x4E, count: 32).base64EncodedString())","expires_at":"2026-11-09T00:02:00Z"}"#, "application/json"),
        (200, provisionedBody(credentialID: Data(repeating: 0x5E, count: 16), notAfter: "2026-11-16T00:00:00Z", notBefore: "2026-11-09T00:00:00Z"), "application/json"),
    ]

    func setUp() async throws -> (Card, SwiftDataCardStore, CredentialRecord) {
        _ = try keys.createKey(for: credentialID)
        let record = CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: expires,
                                      groupKeys: ["a1a2a3a4a5a6a7a8": [P256.Signing.PrivateKey().publicKey.x963Representation]], notBefore: issued, renewalURL: URL(string: "http://127.0.0.1:8080"))
        try records.save(record)
        let cards = try SwiftDataCardStore(directory: temporaryDirectory())
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: ["Pintu Lab"], status: .active, credentials: [.ble: credentialID], notAfter: expires)
        try await cards.add(card)
        return (card, cards, record)
    }

    func scheduler(cards: SwiftDataCardStore, transport: any HTTPTransport, clock: ManualClock = ManualClock(), daysAfterIssue: Double,
                   foreground: LockedBox<Bool> = LockedBox(true), onRenewed: @escaping @MainActor () -> Void = {}) -> RenewalScheduler<ManualClock> {
        let now = issued.addingTimeInterval(daysAfterIssue * 86_400)
        return RenewalScheduler(renewer: CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport), clock: clock, now: { now },
                                isForeground: { foreground.value }, onRenewed: onRenewed)
    }

    @Test func kedaluwarsaDiperpanjangSebelumPresentasi() async throws {
        let (card, cards, _) = try await setUp()
        let transport = SequenceTransport(renewReplies)
        await scheduler(cards: cards, transport: transport, daysAfterIssue: 8).beforePresentation(card: card, channel: .ble, context: context)
        #expect(try records.record(for: credentialID)?.notAfter == Date(timeIntervalSince1970: 1_794_787_200))
    }

    @Test func perpanjanganWajibDibatasiWaktu() async throws {
        // Review Focus 5: server lambat tidak boleh menahan tap lebih dari 5 dtk.
        let (card, cards, record) = try await setUp()
        let clock = ManualClock()
        let transport = HangingTransport()
        let scheduler = scheduler(cards: cards, transport: transport, clock: clock, daysAfterIssue: 8)
        let done = LockedBox(false)
        let task = Task { @MainActor in
            await scheduler.beforePresentation(card: card, channel: .ble, context: context)
            done.withLock { $0 = true }
        }
        await clock.waitForSleepers(1)
        #expect(!done.value)
        clock.advance(by: .seconds(5))
        await task.value
        #expect(done.value)
        #expect(try records.record(for: credentialID) == record)
        transport.gate.open()
    }

    @Test func hampirHabisDiperpanjangSetelahTap() async throws {
        let (card, cards, _) = try await setUp()
        let transport = SequenceTransport(renewReplies)
        let scheduler = scheduler(cards: cards, transport: transport, daysAfterIssue: 4)
        await scheduler.beforePresentation(card: card, channel: .ble, context: context)
        #expect(transport.paths.isEmpty)  // tap tidak ditahan
        await scheduler.afterPresentation()
        #expect(transport.paths.count == 2)
        #expect(try records.record(for: credentialID)?.notAfter == Date(timeIntervalSince1970: 1_794_787_200))
    }

    @Test func masihLamaTidakMenghubungiServer() async throws {
        let (card, cards, _) = try await setUp()
        let transport = SequenceTransport([])
        let scheduler = scheduler(cards: cards, transport: transport, daysAfterIssue: 1)
        await scheduler.beforePresentation(card: card, channel: .ble, context: context)
        await scheduler.afterPresentation()
        #expect(transport.paths.isEmpty)
    }

    @Test func hampirHabisTidakDiperpanjangDiBackground() async throws {
        // Review I2: aliran tap berakhir karena app ke background → tidak ada tanda tangan.
        let (card, cards, record) = try await setUp()
        let foreground = LockedBox(true)
        let transport = SequenceTransport(renewReplies)
        let scheduler = scheduler(cards: cards, transport: transport, daysAfterIssue: 4, foreground: foreground)
        await scheduler.beforePresentation(card: card, channel: .ble, context: context)
        foreground.withLock { $0 = false }
        await scheduler.afterPresentation()
        #expect(transport.paths.isEmpty)
        #expect(try records.record(for: credentialID) == record)
    }

    @Test func tidakMenandatanganiBilaKeBackgroundSetelahChallenge() async throws {
        // Review I2/M2: cek foreground tepat sebelum tanda tangan, bukan hanya di awal.
        let (card, cards, _) = try await setUp()
        let foreground = LockedBox(true)
        let transport = FlippingTransport(replies: renewReplies, flip: foreground)
        let scheduler = scheduler(cards: cards, transport: transport, daysAfterIssue: 4, foreground: foreground)
        await scheduler.beforePresentation(card: card, channel: .ble, context: context)
        await scheduler.afterPresentation()
        #expect(transport.paths.value == ["/v1/credentials/\(credentialID.hexString):challenge"])
    }

    @Test func cancelPendingMembuangPekerjaan() async throws {
        let (card, cards, _) = try await setUp()
        let transport = SequenceTransport(renewReplies)
        let scheduler = scheduler(cards: cards, transport: transport, daysAfterIssue: 4)
        await scheduler.beforePresentation(card: card, channel: .ble, context: context)
        scheduler.cancelPending()
        await scheduler.afterPresentation()
        #expect(transport.paths.isEmpty)
    }

    @Test func perpanjanganBerhasilMemberiSinyal() async throws {
        // Review I1: UI memuat ulang daftar kartu setelah perpanjangan sukses.
        let (card, cards, _) = try await setUp()
        let signals = LockedBox(0)
        let scheduler = scheduler(cards: cards, transport: SequenceTransport(renewReplies), daysAfterIssue: 8, onRenewed: { signals.withLock { $0 += 1 } })
        await scheduler.beforePresentation(card: card, channel: .ble, context: context)
        #expect(signals.value == 1)
    }
}

/// Menjawab berurutan, dan mematikan status foreground saat challenge dilayani.
final class FlippingTransport: HTTPTransport, @unchecked Sendable {
    private let replies: LockedBox<[(status: Int, body: String, contentType: String)]>
    let paths = LockedBox<[String]>([])
    private let flip: LockedBox<Bool>

    init(replies: [(status: Int, body: String, contentType: String)], flip: LockedBox<Bool>) {
        self.replies = LockedBox(replies)
        self.flip = flip
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        paths.withLock { $0.append(request.url?.path(percentEncoded: false) ?? "") }
        flip.withLock { $0 = false }
        guard let reply = replies.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else { throw URLError(.cannotConnectToHost) }
        return (Data(reply.body.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": reply.contentType])!)
    }
}

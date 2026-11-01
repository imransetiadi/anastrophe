import ANCore
import ANCrypto
import ANProtocol
import ANTestSupport
import Foundation
import Testing
@testable import ANChannelNFC

final class FakeCardEmulationSession: CardEmulationSession, @unchecked Sendable {
    let events: AsyncStream<CardEmulationEvent>
    private let continuation: AsyncStream<CardEmulationEvent>.Continuation
    private let entries = LockedBox<[String]>([])
    private let invalidateGate: AsyncGate?

    init(invalidateGate: AsyncGate? = nil) {
        (events, continuation) = AsyncStream.makeStream(of: CardEmulationEvent.self)
        self.invalidateGate = invalidateGate
    }

    var log: [String] { entries.value }

    func send(_ event: CardEmulationEvent) { continuation.yield(event) }

    /// Transport untuk `SoftwareReader`: setiap APDU dikirim sebagai event `received`.
    var transport: @Sendable (Data) async throws -> Data {
        { [self] apdu in
            try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Data, any Error>) in
                send(.received(ReceivedAPDU(payload: apdu) { response in reply.resume(returning: response) }))
            }
        }
    }

    func setAlertMessage(_ message: String) async { entries.withLock { $0.append("alert:\(message)") } }
    func startEmulation() async throws { entries.withLock { $0.append("start") } }
    func stopEmulation(success: Bool) async { entries.withLock { $0.append("stop(\(success))") } }
    func invalidate() async {
        await invalidateGate?.wait()
        entries.withLock { $0.append("invalidate") }
    }
}

final class FakeIntents: PresentmentIntentProvider, @unchecked Sendable {
    final class Assertion: PresentmentIntent {}
    struct Rejected: Error {}

    private let lock = NSLock()
    private var failuresRemaining: Int
    private var count = 0
    private weak var last: Assertion?
    private var all: [() -> Bool] = []

    init(failures: Int = 0) {
        failuresRemaining = failures
    }

    var acquireCount: Int { lock.withLock { count } }
    var lastAssertionAlive: Bool { lock.withLock { last != nil } }
    /// Jumlah assertion yang masih dipegang seseorang.
    var liveAssertions: Int { lock.withLock { all.filter { $0() }.count } }

    func acquire() async throws -> any PresentmentIntent {
        try lock.withLock {
            count += 1
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw Rejected()
            }
            let assertion = Assertion()
            last = assertion
            all.append { [weak assertion] in assertion != nil }
            return assertion
        }
    }
}

struct Harness {
    let clock = ManualClock()
    let session = FakeCardEmulationSession()
    /// Bila diisi, setiap `makeSession` memakai sesi berikutnya dari daftar ini.
    let sessionQueue: LockedBox<[FakeCardEmulationSession]>?
    let credential: ANP1TestCredential
    let sessionsMade = LockedBox(0)
    let intents: FakeIntents
    let capabilities: FakeNFCCapabilities
    let authSucceeds: Bool
    let providerAvailable: Bool

    init(intentFailures: Int = 0, capabilities: FakeNFCCapabilities = FakeNFCCapabilities(), authSucceeds: Bool = true, providerAvailable: Bool = true, credential: ANP1TestCredential = ANP1TestCredential(), sessions: [FakeCardEmulationSession]? = nil) {
        self.credential = credential
        sessionQueue = sessions.map { LockedBox($0) }
        intents = FakeIntents(failures: intentFailures)
        self.capabilities = capabilities
        self.authSucceeds = authSucceeds
        self.providerAvailable = providerAvailable
    }

    func coordinator(log: LockedBox<[String]>? = nil) -> HCEPresentmentCoordinator {
        let session = session, sessionsMade = sessionsMade, credential = credential, providerAvailable = providerAvailable, sessionQueue = sessionQueue
        return HCEPresentmentCoordinator(
            gate: NFCGate(capabilities: capabilities, entitled: true),
            config: RemoteConfig(enabledChannels: [.nfcHCE]),
            authenticator: FakeAuthenticator(succeeds: authSucceeds),
            intents: intents,
            alertMessage: "Dekatkan bagian atas iPhone ke pembaca kartu",
            authenticationReason: "Gunakan kartu",
            makeSession: {
                sessionsMade.withLock { $0 += 1 }
                return sessionQueue?.withLock { $0.isEmpty ? nil : $0.removeFirst() } ?? session
            },
            makeProvider: { _ in
                log?.withLock { $0.append("provider") }
                guard providerAvailable else { throw ANError.keyUnavailable }
                return credential.provider()
            },
            prepare: { _ in log?.withLock { $0.append("prepare") } },
            clock: clock
        )
    }
}

extension AsyncStream<PresentmentEvent>.Iterator {
    mutating func rest() async -> [PresentmentEvent] {
        var events: [PresentmentEvent] = []
        while let event = await next() { events.append(event) }
        return events
    }
}

@Suite("Hook prepare HCE (ADR-0023)")
struct HCEPrepareHookTests {
    @Test func prepareDipanggilSetelahAutentikasiSebelumProvider() async {
        let log = LockedBox<[String]>([])
        // Provider gagal setelah tercatat, sehingga aliran selesai tanpa sesi.
        var events = await Harness(providerAvailable: false).coordinator(log: log).present().makeAsyncIterator()
        while await events.next() != nil {}
        #expect(log.value == ["prepare", "provider"])
    }

    @Test func prepareTidakDipanggilBilaAutentikasiGagal() async {
        let log = LockedBox<[String]>([])
        var events = await Harness(authSucceeds: false).coordinator(log: log).present().makeAsyncIterator()
        while await events.next() != nil {}
        #expect(log.value.isEmpty)
    }
}

@Suite("Presentasi N-HCE (SDD §6.1, FR-20–FR-22)")
struct HCEPresentmentTests {
    @Test func grantMenghentikanEmulasiSukses() async throws {
        let h = Harness()
        var events = await h.coordinator().present().makeAsyncIterator()
        #expect(await events.next() == .waitingForReader)
        h.session.send(.readerDetected)
        #expect(await events.next() == .readerFound(name: nil))

        var reader = h.credential.reader()
        try await reader.run(transport: h.session.transport, credentialKey: h.credential.credentialKey.publicKey, sendGetCert: true, result: .granted)

        #expect(await events.rest() == [.exchanging, .granted])
        #expect(h.session.log == ["alert:Dekatkan bagian atas iPhone ke pembaca kartu", "start", "stop(true)", "invalidate"])
        #expect(!h.intents.lastAssertionAlive)
    }

    @Test func deniedMenghentikanEmulasiGagal() async throws {
        let h = Harness()
        var events = await h.coordinator().present().makeAsyncIterator()
        _ = await events.next()
        h.session.send(.readerDetected)
        _ = await events.next()
        var reader = h.credential.reader()
        try await reader.run(transport: h.session.transport, credentialKey: h.credential.credentialKey.publicKey, sendGetCert: false, result: .denied(reason: 0x05))
        #expect(await events.rest() == [.exchanging, .denied(reason: .zoneNotAllowed)])
        #expect(h.session.log.suffix(2) == ["stop(false)", "invalidate"])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [(ANP1TestCredential(notAfter: .now.addingTimeInterval(-60)), DenyReason.expired), (ANP1TestCredential(suspended: true), .suspended)])
    func kredensialLokalTidakBerlakuDitolakJelas(credential: ANP1TestCredential, reason: DenyReason) async {
        // Temuan review I5: ponsel menjawab 6985 lalu sesi berakhir dengan alasan yang jelas.
        let h = Harness(credential: credential)
        var events = await h.coordinator().present().makeAsyncIterator()
        _ = await events.next()
        h.session.send(.readerDetected)
        _ = await events.next()
        var reader = h.credential.reader()
        await #expect(throws: SoftwareReader.Failure.status(Data([0x69, 0x85]))) {
            try await reader.run(transport: h.session.transport, credentialKey: h.credential.credentialKey.publicKey, sendGetCert: false, result: .granted)
        }
        #expect(await events.rest() == [.exchanging, .denied(reason: reason)])
        #expect(h.session.log.suffix(2) == ["stop(false)", "invalidate"])
    }

    @Test func autentikasiBatalTanpaAssertion() async {
        let h = Harness(authSucceeds: false)
        var events = await h.coordinator().present().makeAsyncIterator()
        #expect(await events.rest() == [.cancelled])
        #expect(h.intents.acquireCount == 0)
        #expect(h.sessionsMade.value == 0)
    }

    @Test func kunciTidakTersediaTanpaAssertion() async {
        // Review Focus 3 di tingkat kanal: kunci hilang → presentasi tidak dicoba.
        let h = Harness(providerAvailable: false)
        var events = await h.coordinator().present().makeAsyncIterator()
        #expect(await events.rest() == [.cancelled])
        #expect(h.intents.acquireCount == 0)
        #expect(h.sessionsMade.value == 0)
    }

    @Test func timeout60Detik() async {
        let h = Harness()
        var events = await h.coordinator().present().makeAsyncIterator()
        #expect(await events.next() == .waitingForReader)
        await h.clock.waitForSleepers(1)
        h.clock.advance(by: .seconds(60))
        #expect(await events.rest() == [.timedOut])
        #expect(h.session.log.last == "invalidate")
        #expect(!h.intents.lastAssertionAlive)
    }

    @Test func cooldown15Detik() async {
        let h = Harness(intentFailures: 1)
        let coordinator = h.coordinator()
        var events = await coordinator.present().makeAsyncIterator()
        #expect(await events.next() == .coolingDown(seconds: 15))
        await h.clock.waitForSleepers(1)
        h.clock.advance(by: .seconds(14))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.intents.acquireCount == 1)
        h.clock.advance(by: .seconds(1))
        #expect(await events.next() == .waitingForReader)
        #expect(h.intents.acquireCount == 2)
        await coordinator.cancel()
        #expect(await events.rest() == [.cancelled])
    }

    @Test func readerDeselectedKembaliMenunggu() async {
        let h = Harness()
        let coordinator = h.coordinator()
        var events = await coordinator.present().makeAsyncIterator()
        _ = await events.next()
        h.session.send(.readerDetected)
        #expect(await events.next() == .readerFound(name: nil))
        h.session.send(.readerDeselected)
        #expect(await events.next() == .waitingForReader)
        await coordinator.cancel()
        #expect(await events.rest() == [.cancelled])
    }

    @Test func transmissionErrorRetrySekali() async {
        let h = Harness()
        let coordinator = h.coordinator()
        var events = await coordinator.present().makeAsyncIterator()
        _ = await events.next()
        h.session.send(.readerDetected)
        _ = await events.next()
        let attempts = LockedBox(0)
        h.session.send(.received(ReceivedAPDU(payload: h.credential.reader().selectCommand()) { _ throws(CardEmulationError) in
            attempts.withLock { $0 += 1 }
            throw .transmission
        }))
        #expect(await events.next() == .exchanging)
        #expect(await events.next() == .waitingForReader)
        #expect(attempts.value == 2)
        await coordinator.cancel()
        #expect(await events.rest() == [.cancelled])
    }

    @Test func backgroundMembatalkanSesi() async {
        // Review Focus 2: app ke background di tengah presentasi.
        let h = Harness()
        let coordinator = h.coordinator()
        var events = await coordinator.present().makeAsyncIterator()
        _ = await events.next()
        h.session.send(.readerDetected)
        #expect(await events.next() == .readerFound(name: nil))
        await coordinator.cancel()
        #expect(await events.rest() == [.cancelled])
        #expect(h.session.log.last == "invalidate")
        #expect(!h.session.log.contains { $0.hasPrefix("stop") })
        #expect(!h.intents.lastAssertionAlive)
    }

    @Test(.timeLimit(.minutes(1)))
    func presentasiBaruTidakDilepasRunLama() async throws {
        // Minor 9: run lama yang sedang membersihkan diri tidak boleh melepas assertion run baru.
        let gate = AsyncGate()
        let h = Harness(sessions: [FakeCardEmulationSession(invalidateGate: gate), FakeCardEmulationSession()])
        let coordinator = h.coordinator()
        var first = await coordinator.present().makeAsyncIterator()
        #expect(await first.next() == .waitingForReader)
        var second = await coordinator.present().makeAsyncIterator()
        try await Task.sleep(for: .milliseconds(100))  // beri kesempatan run baru berjalan lebih dulu
        gate.open()
        #expect(await first.rest() == [.cancelled])
        #expect(await second.next() == .waitingForReader)
        #expect(h.intents.liveAssertions == 1)
        await coordinator.cancel()
        #expect(await second.rest() == [.cancelled])
        #expect(h.intents.liveAssertions == 0)
    }

    @Test func batasWaktuSistemMenjadiTimeout() async {
        let h = Harness()
        var events = await h.coordinator().present().makeAsyncIterator()
        _ = await events.next()
        h.session.send(.invalidated(.timeLimit))
        #expect(await events.rest() == [.timedOut])
    }

    @Test func gatingGagalTidakMembuatSesi() async {
        let h = Harness(capabilities: FakeNFCCapabilities(cardSessionEligible: false))
        var events = await h.coordinator().present().makeAsyncIterator()
        #expect(await events.rest() == [.cancelled])
        #expect(h.sessionsMade.value == 0)
        #expect(h.intents.acquireCount == 0)
    }
}

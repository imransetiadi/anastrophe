import ANCore
import ANCrypto
import ANProtocol
import ANTestSupport
import Foundation
import Testing
@testable import ANChannelBLE

struct LinkDown: Error {}

/// Link BLE palsu. Sisi "reader" mengirim frame perintah dan membaca frame yang ditulis ponsel.
final class FakeBLELink: BLELink, @unchecked Sendable {
    let mtu: Int
    let commands: AsyncThrowingStream<Data, any Error>
    private let commandSink: AsyncThrowingStream<Data, any Error>.Continuation
    private let phoneFrames: AsyncStream<Data>
    private let phoneSink: AsyncStream<Data>.Continuation
    private var phoneIterator: AsyncStream<Data>.Iterator
    private let disconnectedBox = LockedBox(false)

    init(mtu: Int = 185) {
        self.mtu = mtu
        (commands, commandSink) = AsyncThrowingStream.makeStream(of: Data.self)
        (phoneFrames, phoneSink) = AsyncStream.makeStream(of: Data.self)
        phoneIterator = phoneFrames.makeAsyncIterator()
    }

    var disconnected: Bool { disconnectedBox.value }

    func write(_ frame: Data) async throws {
        #expect(frame.count <= mtu)
        phoneSink.yield(frame)
    }

    func disconnect() async { disconnectedBox.withLock { $0 = true } }

    func fail(with error: any Error = LinkDown()) { commandSink.finish(throwing: error) }

    /// Pesan utuh berikutnya yang ditulis ponsel.
    func nextPhoneMessage() async throws -> (BLEFrame.MessageType, Data) {
        var assembler = BLEFrameAssembler()
        while let raw = await phoneIterator.next() {
            if let message = try assembler.append(BLEFrame(decoding: raw)) { return message }
        }
        throw LinkDown()
    }

    /// Transport APDU untuk `SoftwareReader`: SELECT dijawab oleh HELLO ponsel (SDD §7.9).
    func transport(_ apdu: Data) async throws -> Data {
        if apdu[1] == 0xA4 {
            let (type, fci) = try await nextPhoneMessage()
            #expect(type == .hello)
            return fci + Data([0x90, 0x00])
        }
        let type = try #require(BLEFrame.MessageType(rawValue: apdu[1]))
        for frame in BLEFrame.fragment(type: type, payload: apdu.count > 5 ? Data(apdu.dropFirst(5)) : Data(), mtu: mtu) {
            commandSink.yield(frame.encoded())
        }
        let (responseType, payload) = try await nextPhoneMessage()
        #expect(responseType == type)
        return payload
    }
}

final class FakeBLECentral: BLECentral, @unchecked Sendable {
    let advertisements: [BLEReaderAdvertisement]
    let link: FakeBLELink
    let scanError: (any Error)?
    let connectHangs: Bool
    private let scans = LockedBox(0)
    private let connects = LockedBox<[UUID]>([])
    private let cancelledConnect = LockedBox(false)

    init(advertisements: [BLEReaderAdvertisement], link: FakeBLELink = FakeBLELink(), scanError: (any Error)? = nil, connectHangs: Bool = false) {
        self.advertisements = advertisements
        self.link = link
        self.scanError = scanError
        self.connectHangs = connectHangs
    }

    var scanCount: Int { scans.value }
    var connectedIDs: [UUID] { connects.value }
    var connectWasCancelled: Bool { cancelledConnect.value }

    func scan(_ window: ScanWindow) async throws -> [BLEReaderAdvertisement] {
        scans.withLock { $0 += 1 }
        if let scanError { throw scanError }
        return advertisements
    }

    func connect(_ id: UUID) async throws -> any BLELink {
        connects.withLock { $0.append(id) }
        if connectHangs {
            do {
                try await Task.sleep(for: .seconds(3600))  // reader menghilang setelah pindai
            } catch {
                cancelledConnect.withLock { $0 = true }
                throw error
            }
        }
        return link
    }
}

func advertisement(rssi: Int, id: UUID = UUID()) -> BLEReaderAdvertisement {
    BLEReaderAdvertisement(id: id, groupID: Data(repeating: 0xA1, count: 8), rssi: rssi)
}

struct BLEHarness {
    let clock = ManualClock()
    let credential: ANP1TestCredential
    let central: FakeBLECentral
    let foreground: LockedBox<Bool>
    let authSucceeds: Bool

    init(advertisements: [BLEReaderAdvertisement], mtu: Int = 185, foreground: Bool = true, authSucceeds: Bool = true, credential: ANP1TestCredential = ANP1TestCredential(), scanError: (any Error)? = nil, connectHangs: Bool = false) {
        self.credential = credential
        central = FakeBLECentral(advertisements: advertisements, link: FakeBLELink(mtu: mtu), scanError: scanError, connectHangs: connectHangs)
        self.foreground = LockedBox(foreground)
        self.authSucceeds = authSucceeds
    }

    func coordinator() -> BLETapCoordinator<ManualClock> {
        let credential = credential, foreground = foreground
        return BLETapCoordinator(
            central: central,
            authenticator: FakeAuthenticator(succeeds: authSucceeds),
            authenticationReason: "Gunakan kartu",
            makeProvider: { _ in credential.provider() },
            isForeground: { foreground.value },
            clock: clock
        )
    }

    /// Reader perangkat lunak menjalankan transaksi penuh lewat link palsu.
    func runReader(result: ANP1Result = .granted, sendGetCert: Bool = false) async throws {
        var reader = credential.reader()
        let link = central.link
        try await reader.run(transport: { try await link.transport($0) }, credentialKey: credential.credentialKey.publicKey, sendGetCert: sendGetCert, result: result)
    }
}

extension AsyncStream<PresentmentEvent>.Iterator {
    mutating func rest() async -> [PresentmentEvent] {
        var events: [PresentmentEvent] = []
        while let event = await next() { events.append(event) }
        return events
    }
}

@Suite("Pemilihan reader & rate-limit (FR-83)")
struct BLESelectionTests {
    @Test func pilihRSSITertinggiDiAtasAmbang() {
        let near = advertisement(rssi: -50), far = advertisement(rssi: -52), weak = advertisement(rssi: -60)
        #expect(BLEReaderSelector.choose([far, weak, near]) == near)
        #expect(BLEReaderSelector.choose([weak]) == nil)
        #expect(BLEReaderSelector.choose([weak], threshold: -65) == weak)
    }

    @Test func rateLimiterSatuPerTigaDetik() {
        let clock = ManualClock()
        var limiter = ReaderRateLimiter<ManualClock.Instant>()
        let reader = UUID()
        let first = limiter.allow(reader, at: clock.now)
        let tooSoon = limiter.allow(reader, at: clock.now.advanced(by: .seconds(2)))
        let remaining = limiter.remaining(reader, at: clock.now.advanced(by: .seconds(2)))
        let otherReader = limiter.allow(UUID(), at: clock.now.advanced(by: .seconds(2)))
        let afterInterval = limiter.allow(reader, at: clock.now.advanced(by: .seconds(3)))
        #expect([first, tooSoon, otherReader, afterInterval] == [true, false, true, true])
        #expect(remaining == .seconds(1))
    }
}

@Suite("Jendela pindai early exit (ADR-0019, NFR-P04)")
struct ScanWindowTests {
    @Test func berhentiSetelahReaderMemenuhiAmbangDanJedaStabil() {
        var window = ScanWindow(threshold: -55, settle: .milliseconds(300), maximum: .seconds(5))
        #expect(!window.shouldStop(elapsed: .milliseconds(100)))
        window.record(rssi: -70, at: .milliseconds(150))  // di bawah ambang: tidak memicu
        #expect(!window.shouldStop(elapsed: .milliseconds(450)))
        window.record(rssi: -50, at: .milliseconds(500))
        #expect(!window.shouldStop(elapsed: .milliseconds(799)))
        #expect(window.shouldStop(elapsed: .milliseconds(800)))
    }

    @Test func readerPertamaYangMemenuhiMenentukanJeda() {
        var window = ScanWindow(threshold: -55, settle: .milliseconds(300), maximum: .seconds(5))
        window.record(rssi: -54, at: .milliseconds(200))
        window.record(rssi: -40, at: .milliseconds(450))  // reader lain masih dibandingkan dalam jeda
        #expect(window.shouldStop(elapsed: .milliseconds(500)))
    }

    @Test func berhentiPadaBatasMaksimum() {
        let window = ScanWindow(threshold: -55, settle: .milliseconds(300), maximum: .seconds(5))
        #expect(!window.shouldStop(elapsed: .milliseconds(4_999)))
        #expect(window.shouldStop(elapsed: .seconds(5)))
    }
}

@Suite("Presentasi Tap BLE (SDD §6.3, FR-80–FR-83)")
struct BLETapTests {
    @Test(arguments: [(BLEError.poweredOff, ChannelAvailability.bluetoothOff), (.unauthorized, .bluetoothUnauthorized)])
    func bluetoothTidakTersediaMemberiPanduan(error: BLEError, availability: ChannelAvailability) async {
        // Temuan review I2: bukan sekadar "Dibatalkan".
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)], scanError: error)
        var events = await h.coordinator().tap().makeAsyncIterator()
        #expect(await events.rest() == [.waitingForReader, .unavailable(availability)])
    }

    @Test func bluetoothDimatikanDiTengahTransaksiMemberiPanduan() async throws {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)])
        var events = await h.coordinator().tap().makeAsyncIterator()
        _ = await events.next()
        _ = await events.next()
        _ = try await h.central.link.nextPhoneMessage()
        h.central.link.fail(with: BLEError.poweredOff)
        #expect(await events.rest() == [.unavailable(.bluetoothOff)])
        #expect(h.central.link.disconnected)
    }

    @Test(.timeLimit(.minutes(1)))
    func connectMenggantungBerakhirTimeout() async {
        // Temuan review I3: reader menjauh setelah pindai → tidak menunggu tanpa batas.
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)], connectHangs: true)
        var events = await h.coordinator().tap().makeAsyncIterator()
        #expect(await events.next() == .waitingForReader)
        #expect(await events.next() == .readerFound(name: nil))
        await h.clock.waitForSleepers(1)
        h.clock.advance(by: .seconds(3))
        #expect(await events.rest() == [.timedOut])
        #expect(h.central.connectWasCancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func kredensialKedaluwarsaDitolakJelas() async throws {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)], credential: ANP1TestCredential(notAfter: .now.addingTimeInterval(-60)))
        var events = await h.coordinator().tap().makeAsyncIterator()
        await #expect(throws: SoftwareReader.Failure.status(Data([0x69, 0x85]))) { try await h.runReader() }
        #expect(await events.rest().last == .denied(reason: .expired))
        #expect(h.central.link.disconnected)
    }

    @Test func connectKeReaderTerdekat() async {
        let near = advertisement(rssi: -50)
        let h = BLEHarness(advertisements: [advertisement(rssi: -52), near])
        let coordinator = h.coordinator()
        var events = await coordinator.tap().makeAsyncIterator()
        #expect(await events.next() == .waitingForReader)
        #expect(await events.next() == .readerFound(name: nil))
        await coordinator.cancel()
        #expect(await events.rest() == [.cancelled])
        #expect(h.central.connectedIDs == [near.id])
    }

    @Test func diBawahAmbangTidakAdaTransaksi() async {
        let h = BLEHarness(advertisements: [advertisement(rssi: -70)])
        var events = await h.coordinator().tap().makeAsyncIterator()
        #expect(await events.rest() == [.waitingForReader, .readerOutOfRange])  // Minor 8, TC-PRSB-05
        #expect(h.central.connectedIDs.isEmpty)
    }

    @Test func mtuKecilTetapGrant() async throws {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)], mtu: 23)
        var events = await h.coordinator().tap().makeAsyncIterator()
        try await h.runReader(sendGetCert: true)
        #expect(await events.rest() == [.waitingForReader, .readerFound(name: nil), .exchanging, .granted])
        #expect(h.central.link.disconnected)
    }

    @Test func deniedDiteruskan() async throws {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)])
        var events = await h.coordinator().tap().makeAsyncIterator()
        try await h.runReader(result: .denied(reason: 0x02))
        #expect(await events.rest().last == .denied(reason: .suspended))
    }

    @Test func rateLimitTigaDetik() async throws {
        let reader = advertisement(rssi: -45)
        let h = BLEHarness(advertisements: [reader])
        let coordinator = h.coordinator()
        var first = await coordinator.tap().makeAsyncIterator()
        try await h.runReader()
        #expect(await first.rest().last == .granted)

        var second = await coordinator.tap().makeAsyncIterator()
        #expect(await second.next() == .waitingForReader)
        #expect(await second.next() == .coolingDown(seconds: 3))
        #expect(h.central.connectedIDs.count == 1)
        await coordinator.cancel()
        #expect(await second.rest() == [.cancelled])
        #expect(h.central.connectedIDs.count == 1)
    }

    @Test func tidakJalanDiBackground() async {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)], foreground: false)
        var events = await h.coordinator().tap().makeAsyncIterator()
        #expect(await events.rest() == [.cancelled])
        #expect(h.central.scanCount == 0)
    }

    @Test func autentikasiBatalTanpaPemindaian() async {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)], authSucceeds: false)
        var events = await h.coordinator().tap().makeAsyncIterator()
        #expect(await events.rest() == [.cancelled])
        #expect(h.central.scanCount == 0)
    }

    @Test func bluetoothMatiDiTengahTransaksi() async throws {
        // Review Focus 4: link putus → sesi berakhir jelas, tidak menggantung.
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)])
        var events = await h.coordinator().tap().makeAsyncIterator()
        #expect(await events.next() == .waitingForReader)
        #expect(await events.next() == .readerFound(name: nil))
        _ = try await h.central.link.nextPhoneMessage()  // HELLO sudah ditulis
        h.central.link.fail()
        #expect(await events.rest() == [.cancelled])
        #expect(h.central.link.disconnected)
    }

    @Test func readerDiamBerakhirTimeout() async throws {
        let h = BLEHarness(advertisements: [advertisement(rssi: -45)])
        var events = await h.coordinator().tap().makeAsyncIterator()
        _ = await events.next()
        _ = await events.next()
        _ = try await h.central.link.nextPhoneMessage()
        await h.clock.waitForSleepers(1)
        h.clock.advance(by: .seconds(5))
        #expect(await events.rest() == [.timedOut])
        #expect(h.central.link.disconnected)
    }
}

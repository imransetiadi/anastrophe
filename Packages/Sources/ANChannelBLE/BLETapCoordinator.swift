import ANCore
import ANCrypto
import ANProtocol
import Foundation

/// Presentasi kanal B "Tap" (SDD §6.3): foreground saja (ADR-0012), pindai paralel dengan
/// autentikasi dan berhenti cepat (ADR-0019), reader dengan RSSI tertinggi di atas ambang,
/// lalu ANP/1 lewat framing BLE (§7.9).
public actor BLETapCoordinator<C: Clock> where C.Duration == Duration {
    /// Batas atas pemindaian; biasanya berhenti jauh lebih cepat (early exit, ADR-0019).
    public static var scanDuration: Duration { .seconds(5) }
    /// Jeda setelah reader pertama memenuhi ambang, untuk membandingkan RSSI (FR-83).
    public static var scanSettle: Duration { .milliseconds(300) }
    /// Batas connect + persiapan GATT; reader yang menjauh tidak boleh menggantung UI.
    public static var connectTimeout: Duration { .seconds(3) }
    /// Batas pertukaran setelah terhubung, agar reader yang diam tidak menggantung UI.
    public static var exchangeTimeout: Duration { .seconds(5) }

    private enum Input: Equatable, Sendable {
        case frame(Data)
        case linkEnded(ChannelAvailability?)
        case timeout
    }

    private let central: any BLECentral
    private let authenticator: any UserAuthenticator
    private let authenticationReason: String
    private let makeProvider: @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider
    /// Dipanggil setelah autentikasi sukses, sebelum provider dibuat (perpanjangan, ADR-0023).
    private let prepare: @Sendable (AuthorizedContext) async -> Void
    private let isForeground: @Sendable () -> Bool
    private let clock: C
    private let rssiThreshold: Int
    private var limiter = ReaderRateLimiter<C.Instant>()
    private var running: Task<Void, Never>?

    public init(
        central: any BLECentral,
        authenticator: any UserAuthenticator,
        authenticationReason: String,
        makeProvider: @escaping @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider,
        prepare: @escaping @Sendable (AuthorizedContext) async -> Void = { _ in },
        isForeground: @escaping @Sendable () -> Bool,
        clock: C,
        rssiThreshold: Int = BLEReaderSelector.defaultThreshold
    ) {
        self.central = central
        self.authenticator = authenticator
        self.authenticationReason = authenticationReason
        self.makeProvider = makeProvider
        self.prepare = prepare
        self.isForeground = isForeground
        self.clock = clock
        self.rssiThreshold = rssiThreshold
    }

    public func tap() -> AsyncStream<PresentmentEvent> {
        let previous = running
        previous?.cancel()
        let (stream, events) = AsyncStream.makeStream(of: PresentmentEvent.self)
        running = Task {
            await previous?.value  // satu koneksi pada satu waktu; run lama memutus link dulu
            await self.run(events)
        }
        return stream
    }

    /// Dipanggil saat app meninggalkan foreground.
    public func cancel() {
        running?.cancel()
    }

    private func run(_ out: AsyncStream<PresentmentEvent>.Continuation) async {
        guard isForeground(), !Task.isCancelled else { return finish(out, with: .cancelled) }
        // ADR-0019: pemindaian berjalan bersamaan dengan autentikasi (Face ID) agar NFR-P04
        // tercapai. Child task ini otomatis dibatalkan bila autentikasi gagal atau app ke
        // background; connect tetap hanya setelah autentikasi berhasil.
        async let scanned = central.scan(ScanWindow(threshold: rssiThreshold, settle: Self.scanSettle, maximum: Self.scanDuration))
        guard let context = try? await authenticator.authenticate(reason: authenticationReason),
              isForeground(), !Task.isCancelled
        else { return finish(out, with: .cancelled) }
        await prepare(context)
        guard let provider = try? makeProvider(context), isForeground(), !Task.isCancelled else {
            return finish(out, with: .cancelled)
        }

        out.yield(.waitingForReader)
        let advertisements: [BLEReaderAdvertisement]
        do {
            advertisements = try await scanned
        } catch {
            return finish(out, with: Self.terminal(for: error))
        }
        guard !Task.isCancelled else { return finish(out, with: .cancelled) }
        guard let reader = BLEReaderSelector.choose(advertisements, threshold: rssiThreshold) else {
            return finish(out, with: .readerOutOfRange)
        }
        let wait = limiter.remaining(reader.id, at: clock.now)
        if wait > .zero {
            out.yield(.coolingDown(seconds: Int((Double(wait.components.seconds) + Double(wait.components.attoseconds) / 1e18).rounded(.up))))
            guard (try? await clock.sleep(for: wait)) != nil else { return finish(out, with: .cancelled) }
        }
        _ = limiter.allow(reader.id, at: clock.now)

        out.yield(.readerFound(name: nil))
        let link: any BLELink
        do {
            link = try await connect(reader.id)
        } catch BLEError.timeout {
            return finish(out, with: .timedOut)
        } catch {
            return finish(out, with: Self.terminal(for: error))
        }
        let terminal = await exchange(link: link, responder: ANP1Responder(credentials: provider), out: out)
        await link.disconnect()
        finish(out, with: terminal)
    }

    /// Connect + persiapan GATT dengan batas waktu; link yang terlambat terhubung diputus.
    private func connect(_ id: UUID) async throws -> any BLELink {
        let central = central, clock = clock
        return try await withThrowingTaskGroup(of: (any BLELink)?.self) { group in
            group.addTask { try await central.connect(id) }
            group.addTask {
                try await clock.sleep(for: Self.connectTimeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            if let first { return first }
            while let late = try? await group.next() {
                await late?.disconnect()
            }
            throw BLEError.timeout
        }
    }

    /// Bluetooth mati/izin ditolak → panduan; selain itu batal.
    private static func terminal(for error: any Error) -> PresentmentEvent {
        if let availability = (error as? BLEError)?.availability { return .unavailable(availability) }
        return .cancelled
    }

    private func exchange(link: any BLELink, responder initial: ANP1Responder, out: AsyncStream<PresentmentEvent>.Continuation) async -> PresentmentEvent {
        var responder = initial
        // SELECT tidak dipakai di BLE: responder di-SELECT internal, FCI dikirim sebagai HELLO.
        let fci = responder.handle(Data([0x00, 0xA4, 0x04, 0x00, UInt8(ANP1.aid.count)]) + ANP1.aid).dropLast(2)
        do {
            try await write(type: .hello, payload: Data(fci), to: link)
        } catch {
            return Self.terminal(for: error)
        }

        let (inputs, input) = AsyncStream.makeStream(of: Input.self)
        let commands = link.commands
        let forward = Task {
            do {
                for try await frame in commands { input.yield(.frame(frame)) }
                input.yield(.linkEnded(nil))
            } catch {
                input.yield(.linkEnded((error as? BLEError)?.availability))
            }
        }
        let clock = clock
        let timer = Task {
            if (try? await clock.sleep(for: Self.exchangeTimeout)) != nil { input.yield(.timeout) }
        }
        defer {
            forward.cancel()
            timer.cancel()
        }

        var assembler = BLEFrameAssembler()
        var exchanging = false
        for await item in inputs {
            guard case .frame(let raw) = item else {
                switch item {
                case .timeout: return .timedOut
                case .linkEnded(let availability?): return .unavailable(availability)
                default: return .cancelled
                }
            }
            guard let frame = try? BLEFrame(decoding: raw), let message = try? assembler.append(frame) else { continue }
            if !exchanging {
                exchanging = true
                out.yield(.exchanging)
            }
            let (type, payload) = message
            let command = try? CommandAPDU(cla: 0x80, ins: type.rawValue, data: payload).encoded()
            let response = command.map { responder.handle($0) } ?? StatusWord.wrongLength.bytes
            do {
                try await write(type: type, payload: response, to: link)
            } catch {
                return Self.terminal(for: error)
            }
            if let failure = responder.localFailure {
                return .denied(reason: failure == .credentialExpired ? .expired : .suspended)
            }
            switch responder.outcome {
            case .granted?: return .granted
            case .denied(let code)?: return .denied(reason: DenyReason(anp1Code: code))
            case nil: continue
            }
        }
        return .cancelled  // dibatalkan (background)
    }

    private func write(type: BLEFrame.MessageType, payload: Data, to link: any BLELink) async throws {
        for frame in BLEFrame.fragment(type: type, payload: payload, mtu: link.mtu) {
            try await link.write(frame.encoded())
        }
    }

    private func finish(_ out: AsyncStream<PresentmentEvent>.Continuation, with event: PresentmentEvent) {
        out.yield(event)
        out.finish()
    }
}

extension BLETapCoordinator where C == ContinuousClock {
    public init(
        central: any BLECentral,
        authenticator: any UserAuthenticator,
        authenticationReason: String,
        makeProvider: @escaping @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider,
        prepare: @escaping @Sendable (AuthorizedContext) async -> Void = { _ in },
        isForeground: @escaping @Sendable () -> Bool
    ) {
        self.init(central: central, authenticator: authenticator, authenticationReason: authenticationReason, makeProvider: makeProvider, prepare: prepare, isForeground: isForeground, clock: ContinuousClock())
    }
}

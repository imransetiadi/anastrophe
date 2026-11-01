import ANCore
import ANCrypto
import ANProtocol
import Foundation

/// Presentasi kanal N-HCE (SDD §6.1): gating → autentikasi → assertion →
/// `CardSession` → pertukaran ANP/1 → hasil.
///
/// Assertion hanya diambil setelah pengguna memilih kartu dan berhasil
/// diautentikasi (FR-21). Sesi dibuat hanya setelah gating lolos, karena
/// `CardSession()` tanpa entitlement memicu `fatalError` (O-A02).
public actor HCEPresentmentCoordinator {
    private enum Input: Sendable {
        case event(CardEmulationEvent)
        case timeout
    }

    private let gate: NFCGate
    private let config: RemoteConfig
    private let authenticator: any UserAuthenticator
    private let intents: any PresentmentIntentProvider
    private let alertMessage: String
    private let authenticationReason: String
    private let makeSession: @Sendable () async throws -> any CardEmulationSession
    private let makeProvider: @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider
    private let clock: any Clock<Duration>
    private var running: Task<Void, Never>?

    /// Assertion milik satu run; dilepas oleh run itu sendiri, bukan oleh run lain.
    private final class IntentHolder {
        var intent: (any PresentmentIntent)?
    }

    public init(
        gate: NFCGate,
        config: RemoteConfig,
        authenticator: any UserAuthenticator,
        intents: any PresentmentIntentProvider,
        alertMessage: String,
        authenticationReason: String,
        makeSession: @escaping @Sendable () async throws -> any CardEmulationSession,
        makeProvider: @escaping @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.gate = gate
        self.config = config
        self.authenticator = authenticator
        self.intents = intents
        self.alertMessage = alertMessage
        self.authenticationReason = authenticationReason
        self.makeSession = makeSession
        self.makeProvider = makeProvider
        self.clock = clock
    }

    /// Memulai presentasi untuk kartu yang dipilih pengguna. Presentasi sebelumnya dibatalkan.
    public func present() -> AsyncStream<PresentmentEvent> {
        let previous = running
        previous?.cancel()
        let (stream, events) = AsyncStream.makeStream(of: PresentmentEvent.self)
        running = Task {
            await previous?.value  // run sebelumnya selesai membersihkan diri lebih dulu
            await self.run(events)
        }
        return stream
    }

    /// Dipanggil saat app meninggalkan foreground (`scenePhase != .active`).
    public func cancel() {
        running?.cancel()
    }

    private func run(_ out: AsyncStream<PresentmentEvent>.Continuation) async {
        let holder = IntentHolder()
        guard await gate.availability(.nfcHCE, config: config) == .available,
              let context = try? await authenticator.authenticate(reason: authenticationReason),
              let provider = try? makeProvider(context),
              await acquireIntent(out, into: holder),
              let session = try? await makeSession()
        else {
            finish(out, with: .cancelled, releasing: holder)
            return
        }
        await session.setAlertMessage(alertMessage)
        let terminal = await exchange(session: session, responder: ANP1Responder(credentials: provider), out: out)
        await session.invalidate()
        finish(out, with: terminal, releasing: holder)
    }

    /// Assertion; bila ditolak, tunggu cooldown lalu coba tepat sekali lagi (O-A05).
    private func acquireIntent(_ out: AsyncStream<PresentmentEvent>.Continuation, into holder: IntentHolder) async -> Bool {
        guard !Task.isCancelled else { return false }
        if let intent = try? await intents.acquire() {
            holder.intent = intent
            return true
        }
        out.yield(.coolingDown(seconds: Int(PresentmentLimits.hceCooldownSeconds)))
        guard (try? await clock.sleep(for: .seconds(PresentmentLimits.hceCooldownSeconds))) != nil,
              let intent = try? await intents.acquire()
        else { return false }
        holder.intent = intent
        return true
    }

    private func exchange(
        session: any CardEmulationSession,
        responder initial: ANP1Responder,
        out: AsyncStream<PresentmentEvent>.Continuation
    ) async -> PresentmentEvent {
        var responder = initial
        let (inputs, input) = AsyncStream.makeStream(of: Input.self)
        let sessionEvents = session.events
        let forward = Task {
            for await event in sessionEvents { input.yield(.event(event)) }
            input.finish()
        }
        let clock = clock
        let timer = Task {
            if (try? await clock.sleep(for: .seconds(PresentmentLimits.hceEmulationSeconds))) != nil {
                input.yield(.timeout)
            }
        }
        defer {
            forward.cancel()
            timer.cancel()
        }

        out.yield(.waitingForReader)
        var exchanging = false
        for await item in inputs {
            switch item {
            case .timeout:
                return .timedOut
            case .event(.sessionStarted):
                continue
            case .event(.readerDetected):
                exchanging = false
                out.yield(.readerFound(name: nil))
                do { try await session.startEmulation() } catch { out.yield(.waitingForReader) }
            case .event(.readerDeselected):
                exchanging = false
                out.yield(.waitingForReader)
            case .event(.received(let apdu)):
                if !exchanging {
                    exchanging = true
                    out.yield(.exchanging)
                }
                let response = responder.handle(apdu.payload)
                do {
                    try await Self.respond(apdu, with: response)
                } catch {
                    exchanging = false
                    out.yield(.waitingForReader)
                    continue
                }
                if let failure = responder.localFailure {
                    await session.stopEmulation(success: false)
                    return .denied(reason: failure == .credentialExpired ? .expired : .suspended)
                }
                switch responder.outcome {
                case .granted?:
                    await session.stopEmulation(success: true)
                    return .granted
                case .denied(let code)?:
                    await session.stopEmulation(success: false)
                    return .denied(reason: DenyReason(anp1Code: code))
                case nil:
                    continue
                }
            case .event(.invalidated(let reason)):
                return reason == .timeLimit ? .timedOut : .cancelled
            }
        }
        return .cancelled  // dibatalkan (background) atau aliran event sesi berakhir
    }

    /// `transmissionError` dicoba ulang tepat sekali (E04).
    private static func respond(_ apdu: ReceivedAPDU, with response: Data) async throws(CardEmulationError) {
        do {
            try await apdu.respond(response)
        } catch .transmission {
            try await apdu.respond(response)
        }
    }

    private func finish(_ out: AsyncStream<PresentmentEvent>.Continuation, with event: PresentmentEvent, releasing holder: IntentHolder) {
        holder.intent = nil  // melepas assertion milik run ini
        out.yield(event)
        out.finish()
    }
}

import ANCore
import ANCrypto
import Foundation

/// Menjadwalkan perpanjangan sertifikat di sekitar tap (ADR-0023). Sertifikat kedaluwarsa
/// diperpanjang sebelum presentasi, paling lama `mandatoryTimeout`; yang sisa masa berlakunya
/// < 50% diperpanjang setelah tap selesai, sehingga tap tidak ditahan dan tidak ada dua tanda
/// tangan bersamaan pada satu `LAContext`.
@MainActor
final class RenewalScheduler<C: Clock> where C.Duration == Duration {
    static var mandatoryTimeout: Duration { .seconds(5) }

    private let renewer: CredentialRenewer
    private let clock: C
    private let now: @Sendable () -> Date
    private let isForeground: @Sendable () -> Bool
    private let onRenewed: @MainActor () -> Void
    /// Pekerjaan "sisa < 50%" milik satu tap; tap lain tidak menjalankannya.
    private var pending: (card: Card, channel: ChannelKind, context: AuthorizedContext, tap: UUID)?

    init(renewer: CredentialRenewer, clock: C, now: @escaping @Sendable () -> Date = { .now },
         isForeground: @escaping @Sendable () -> Bool = { true }, onRenewed: @escaping @MainActor () -> Void = {}) {
        self.renewer = renewer
        self.clock = clock
        self.now = now
        self.isForeground = isForeground
        self.onRenewed = onRenewed
    }

    /// Dipanggil saat presentasi dibatalkan (mis. app ke background): pekerjaan tertunda dibuang.
    func cancelPending() {
        pending?.context.laContext.invalidate()
        pending = nil
    }

    /// Dipanggil coordinator setelah autentikasi tap, sebelum sesi presentasi dibuat.
    func beforePresentation(card: Card, channel: ChannelKind, context: AuthorizedContext, tap: UUID) async {
        cancelPending()  // tap baru: pekerjaan tap lama dibuang dan konteksnya di-invalidate
        guard let credentialID = card.credentials[channel],
              let record = try? renewer.records.record(for: credentialID),
              record.renewalURL != nil
        else { return }
        switch RenewalPolicy.need(notBefore: record.notBefore, notAfter: record.notAfter, now: now()) {
        case .none:
            break
        case .soon:
            pending = (card, channel, context, tap)
        case .expired:
            await renewBounded(card: card, channel: channel, context: context)
        }
    }

    /// Dipanggil setelah aliran event tap selesai; konteks dilepas setelahnya.
    func afterPresentation(tap: UUID) async {
        guard let job = pending, job.tap == tap else { return }
        pending = nil
        defer { job.context.laContext.invalidate() }
        // Aliran tap juga berakhir saat app ke background; jangan menandatangani di sana.
        guard isForeground() else { return }
        await renewBounded(card: job.card, channel: job.channel, context: job.context)
    }

    /// Bila gagal atau lewat batas waktu, tap tetap dilanjutkan dan gagal tertutup
    /// (`.denied(.expired)`).
    private func renewBounded(card: Card, channel: ChannelKind, context: AuthorizedContext) async {
        let (signal, continuation) = AsyncStream.makeStream(of: Void.self)
        let renewer = renewer, clock = clock, isForeground = isForeground, onRenewed = onRenewed
        let renewal = Task {
            if (try? await renewer.renew(card: card, channel: channel, context: context, shouldSign: { isForeground() && !Task.isCancelled })) != nil {
                await onRenewed()
            }
            continuation.yield()
        }
        let timer = Task {
            try? await clock.sleep(for: Self.mandatoryTimeout)
            continuation.yield()
        }
        for await _ in signal { break }
        timer.cancel()
        renewal.cancel()
    }
}

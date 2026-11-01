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
    private var pending: (card: Card, channel: ChannelKind, context: AuthorizedContext)?

    init(renewer: CredentialRenewer, clock: C, now: @escaping @Sendable () -> Date = { .now }) {
        self.renewer = renewer
        self.clock = clock
        self.now = now
    }

    /// Dipanggil coordinator setelah autentikasi tap, sebelum sesi presentasi dibuat.
    func beforePresentation(card: Card, channel: ChannelKind, context: AuthorizedContext) async {
        pending = nil
        guard let credentialID = card.credentials[channel],
              let record = try? renewer.records.record(for: credentialID),
              record.renewalURL != nil
        else { return }
        switch RenewalPolicy.need(notBefore: record.notBefore, notAfter: record.notAfter, now: now()) {
        case .none:
            break
        case .soon:
            pending = (card, channel, context)
        case .expired:
            await renewBounded(card: card, channel: channel, context: context)
        }
    }

    /// Dipanggil setelah aliran event tap selesai; konteks dilepas setelahnya.
    func afterPresentation() async {
        guard let job = pending else { return }
        pending = nil
        _ = try? await renewer.renew(card: job.card, channel: job.channel, context: job.context)
    }

    /// Bila gagal atau lewat batas waktu, tap tetap dilanjutkan dan gagal tertutup
    /// (`.denied(.expired)`).
    private func renewBounded(card: Card, channel: ChannelKind, context: AuthorizedContext) async {
        let (signal, continuation) = AsyncStream.makeStream(of: Void.self)
        let renewer = renewer, clock = clock
        let renewal = Task {
            _ = try? await renewer.renew(card: card, channel: channel, context: context)
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

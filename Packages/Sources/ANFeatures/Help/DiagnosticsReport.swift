import ANCore
import Foundation

/// Ringkasan kartu untuk laporan diagnostik. Sengaja tanpa id, nama, atau kunci, sehingga rahasia tidak
/// mungkin ikut ke laporan walau pemanggil salah (FR-63, CLAUDE.md aturan 6, ADR-0041).
struct CardSummary: Sendable, Equatable {
    let status: CardStatus
    let channels: [ChannelKind]
    let notAfter: Date?
}

/// Bahan laporan diagnostik: hanya data yang aman dibagikan ke dukungan.
struct DiagnosticsInput: Sendable {
    let appVersion: String
    let build: String
    let osVersion: String
    let locale: String
    let channels: [ChannelKind: ChannelAvailability]
    let serviceConfigured: Bool
    /// Store kartu berhasil dibuka saat app dimulai (`AppServices.storageFailed` false).
    let storageAvailable: Bool
    /// nil bila kartu tidak bisa dibaca; dibedakan dari "tanpa kartu" agar dukungan tidak salah diagnosis.
    let cards: [CardSummary]?
}

/// Teks laporan diagnostik (FR-63): baris `kunci: nilai` dengan label tetap (tidak dilokalisasi) agar
/// dukungan selalu membaca format yang sama. Dibuat di perangkat tanpa jaringan.
enum DiagnosticsReport {
    static func text(_ input: DiagnosticsInput) -> String {
        var lines = [
            "Anastrophe — laporan diagnostik",
            "app: \(input.appVersion) (\(input.build))",
            "ios: \(input.osVersion)",
            "bahasa: \(input.locale)",
        ]
        for kind in ChannelKind.priorityOrder {
            if let availability = input.channels[kind] {
                lines.append("kanal \(kind.rawValue): \(availability)")
            }
        }
        lines.append("penyimpanan: \(input.storageAvailable ? "ok" : "gagal")")
        lines.append("layanan: \(input.serviceConfigured ? "ya" : "tidak")")
        guard let cards = input.cards else {
            lines.append("kartu: tidak terbaca")
            return lines.joined(separator: "\n")
        }
        lines.append("kartu: \(cards.count)")
        for (index, card) in cards.enumerated() {
            let channels = card.channels.isEmpty ? "-" : card.channels.map(\.rawValue).joined(separator: "+")
            let expiry = card.notAfter.map { "berlaku sampai \($0.formatted(.iso8601.year().month().day()))" } ?? "tanpa masa berlaku"
            lines.append("kartu \(index + 1): \(card.status.rawValue), \(channels), \(expiry)")
        }
        return lines.joined(separator: "\n")
    }
}

extension AppServices {
    /// Bahan laporan dari kondisi app saat ini. Penyimpanan yang gagal dibuka atau kartu yang gagal dibaca
    /// dilaporkan sebagai "tidak terbaca", bukan sebagai nol kartu (review akhir Bantuan #2).
    func diagnosticsInput() async -> DiagnosticsInput {
        let info = Bundle.main.infoDictionary
        let cards: [Card]? = storageFailed ? nil : try? await cards.all()
        return DiagnosticsInput(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            channels: await availability(),
            serviceConfigured: apiBaseURL != nil,
            storageAvailable: !storageFailed,
            cards: cards?.map { card in
                CardSummary(status: card.displayStatus(),
                            channels: ChannelKind.priorityOrder.filter { card.credentials[$0] != nil },
                            notAfter: card.notAfter)
            }
        )
    }
}

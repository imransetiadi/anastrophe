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
    let cards: [CardSummary]
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
        lines.append("layanan: \(input.serviceConfigured ? "ya" : "tidak")")
        lines.append("kartu: \(input.cards.count)")
        for (index, card) in input.cards.enumerated() {
            let channels = card.channels.isEmpty ? "-" : card.channels.map(\.rawValue).joined(separator: "+")
            let expiry = card.notAfter.map { "berlaku sampai \($0.formatted(.iso8601.year().month().day()))" } ?? "tanpa masa berlaku"
            lines.append("kartu \(index + 1): \(card.status.rawValue), \(channels), \(expiry)")
        }
        return lines.joined(separator: "\n")
    }
}

extension AppServices {
    /// Bahan laporan dari kondisi app saat ini. Store yang gagal dibaca menghasilkan daftar kartu kosong.
    func diagnosticsInput() async -> DiagnosticsInput {
        let info = Bundle.main.infoDictionary
        let cards = (try? await cards.all()) ?? []
        return DiagnosticsInput(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            channels: await availability(),
            serviceConfigured: apiBaseURL != nil,
            cards: cards.map { card in
                CardSummary(status: card.displayStatus(),
                            channels: ChannelKind.priorityOrder.filter { card.credentials[$0] != nil },
                            notAfter: card.notAfter)
            }
        )
    }
}

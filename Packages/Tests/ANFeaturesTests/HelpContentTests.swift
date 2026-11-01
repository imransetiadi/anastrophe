import ANCore
import Foundation
import Testing
@testable import ANFeatures

@Suite("Konten Bantuan dan FAQ (FR-60, FR-02, FR-27; TC-UX-08, TC-UX-11)")
struct HelpContentTests {
    @Test func faqMencakupSepuluhTopik() {
        // FR-60: perangkat, kartu, maks 8, offline, layar terkunci, hapus, anggota, sharing, pindah, hilang.
        #expect(HelpTopic.allCases.count == 10)
        #expect(HelpTopic.allCases.map(\.rawValue) == ["devices", "cards", "limit", "offline", "lockedScreen", "delete", "members", "sharing", "transfer", "lost"])
        for topic in HelpTopic.allCases {
            #expect(!topic.question.isEmpty && !topic.question.hasPrefix("help."), "\(topic) tanpa pertanyaan")
            #expect(!topic.answer.isEmpty && !topic.answer.hasPrefix("help."), "\(topic) tanpa jawaban")
        }
    }

    @Test func statusKanalMengikutiKelayakan() {
        #expect(HelpContent.status(for: .available) == localized("help.channel.available"))
        #expect(HelpContent.status(for: .bluetoothOff) == localized("help.channel.bluetooth_off"))
        #expect(HelpContent.status(for: .bluetoothUnauthorized) == localized("help.channel.bluetooth_denied"))
        for other: ChannelAvailability? in [.notEligible, .regionBlocked, .unsupportedDevice, .entitlementMissing, .programNotEnabled, nil] {
            #expect(HelpContent.status(for: other) == localized("help.channel.unavailable"))
        }
        // Status berbeda harus terbaca berbeda.
        let texts = Set([ChannelAvailability.available, .bluetoothOff, .bluetoothUnauthorized, .notEligible].map { HelpContent.status(for: $0) })
        #expect(texts.count == 4)
    }

    @Test func jawabanLayarTerkunciMenyebutBukaAppDanAutentikasi() {
        // FR-27: perilaku saat terkunci dijelaskan di FAQ.
        let answer = HelpTopic.lockedScreen.answer.lowercased()
        #expect(answer.contains("face id"))
        #expect(answer.contains("buka") || answer.contains("open"))
    }
}

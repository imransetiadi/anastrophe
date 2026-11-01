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
        #expect(HelpContent.status(for: .unsupportedDevice) == localized("help.channel.unsupported_device"))
        for eligibility: ChannelAvailability in [.notEligible, .regionBlocked] {
            #expect(HelpContent.status(for: eligibility) == localized("help.channel.unavailable"))
        }
        // Review akhir (Minor 6, dinaikkan): penyebab dari build atau program, bukan dari iPhone/wilayah,
        // tidak boleh menyalahkan iPhone atau wilayah pengguna (build tanpa emulasi = entitlementMissing).
        for other: ChannelAvailability? in [.entitlementMissing, .programNotEnabled, nil] {
            #expect(HelpContent.status(for: other) == localized("help.channel.not_yet"))
        }
        let texts = Set([ChannelAvailability.available, .bluetoothOff, .bluetoothUnauthorized, .unsupportedDevice, .notEligible, .entitlementMissing].map { HelpContent.status(for: $0) })
        #expect(texts.count == 6)
    }

    /// Teks katalog per bahasa, tidak bergantung lokal mesin yang menjalankan test.
    func answer(_ topic: String, _ language: String) throws -> String {
        let entry = try #require(try StringCatalogTests.load().strings["help.faq.\(topic).answer"])
        return try #require(entry.localizations?[language]?.stringUnit.value).lowercased()
    }

    @Test func jawabanOfflineSesuaiPerpanjanganSaatDipakai() throws {
        // Review akhir #1: perpanjangan hanya terjadi saat kartu dipakai dengan internet (ADR-0023), dan
        // kartu yang kedaluwarsa baru bisa dipakai lagi setelah iPhone terhubung.
        let id = try answer("offline", "id"), en = try answer("offline", "en")
        #expect(id.contains("kedaluwarsa") && id.contains("saat dipakai") && !id.contains("sesekali"))
        #expect(en.contains("expires") && en.contains("when you use") && !en.contains("now and then"))
    }

    @Test func jawabanGantiIPhoneMenghapusDiIPhoneLamaDulu() throws {
        // Review akhir #3: menambah di iPhone baru lebih dulu selalu menunggu persetujuan pengelola.
        for (language, delete, add, login) in [("id", "hapus kartu", "tambahkan kartu", "login"), ("en", "delete the card", "add the card", "signing in")] {
            let text = try answer("transfer", language)
            let deleteRange = try #require(text.range(of: delete), "\(language): tanpa '\(delete)'")
            let addRange = try #require(text.range(of: add), "\(language): tanpa '\(add)'")
            #expect(deleteRange.lowerBound < addRange.lowerBound, "\(language): hapus harus sebelum tambah")
            #expect(!text.contains(login))
        }
    }

    @Test func jawabanLayarTerkunciMenyebutBukaAppDanAutentikasi() {
        // FR-27: perilaku saat terkunci dijelaskan di FAQ.
        let answer = HelpTopic.lockedScreen.answer.lowercased()
        #expect(answer.contains("face id"))
        #expect(answer.contains("buka") || answer.contains("open"))
    }
}

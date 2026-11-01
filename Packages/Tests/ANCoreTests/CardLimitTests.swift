import Testing
@testable import ANCore

@Suite("Batas kartu per perangkat (FR, CLAUDE.md aturan 8)")
struct CardLimitTests {
    @Test func maksimumDelapan() {
        #expect(CardLimit.maxCardsPerDevice == 8)
    }

    @Test(arguments: 0..<8)
    func bolehMenambahDiBawahBatas(count: Int) {
        #expect(CardLimit.canAddCard(currentCount: count))
    }

    @Test(arguments: [8, 9, 20])
    func ditolakSaatPenuh(count: Int) {
        #expect(!CardLimit.canAddCard(currentCount: count))
        #expect(throws: ANError.cardLimitReached) {
            try CardLimit.ensureCanAdd(currentCount: count)
        }
    }
}

@Suite("Pemilihan kanal per kartu (SDD §4.2, FR-05)")
struct ChannelSelectionTests {
    @Test func urutanPrioritas() {
        #expect(ChannelKind.priorityOrder == [.wallet, .nfcSE, .nfcHCE, .ble])
    }

    @Test func pilihKanalTertinggiYangTersedia() {
        let policy: Set<ChannelKind> = [.nfcHCE, .ble]
        let availability: [ChannelKind: ChannelAvailability] = [
            .wallet: .programNotEnabled, .nfcSE: .notEligible, .nfcHCE: .available, .ble: .available,
        ]
        #expect(ChannelSelector.preferred(allowedBySite: policy, availability: availability) == .nfcHCE)
    }

    @Test func kebijakanGedungMengalahkanKetersediaan() {
        let availability: [ChannelKind: ChannelAvailability] = [.nfcHCE: .available, .ble: .available]
        #expect(ChannelSelector.preferred(allowedBySite: [.ble], availability: availability) == .ble)
    }

    @Test func tidakAdaKanal() {
        #expect(ChannelSelector.preferred(allowedBySite: [.ble], availability: [.ble: .bluetoothOff]) == nil)
    }
}

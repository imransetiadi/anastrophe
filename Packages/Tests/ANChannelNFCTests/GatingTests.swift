import ANCore
import Testing
@testable import ANChannelNFC

struct FakeNFCCapabilities: NFCCapabilities {
    var readingAvailable = true
    var cardSessionSupported = true
    var cardSessionEligible = true
    var credentialSessionEligible = true
    let calls = CallLog()

    func isCardSessionEligible() async -> Bool { calls.record("isEligible"); return cardSessionEligible }
    func isCredentialSessionEligible() async -> Bool { credentialSessionEligible }
}

final class CallLog: @unchecked Sendable {
    private(set) var names: [String] = []
    func record(_ name: String) { names.append(name) }
}

@Suite("Gating kelayakan NFC (SDD §5.4, CLAUDE.md aturan 3)")
struct GatingTests {
    let config = RemoteConfig(enabledChannels: [.nfcHCE, .nfcSE])

    @Test func serverMemblokirWilayah() async {
        let gate = NFCGate(capabilities: FakeNFCCapabilities(), entitled: true)
        #expect(await gate.availability(.nfcHCE, config: RemoteConfig(enabledChannels: [.ble])) == .regionBlocked)
    }

    @Test func perangkatTakMendukungTidakMemanggilIsEligible() async {
        let caps = FakeNFCCapabilities(cardSessionSupported: false)
        #expect(await NFCGate(capabilities: caps, entitled: true).availability(.nfcHCE, config: config) == .unsupportedDevice)
        #expect(caps.calls.names.isEmpty)
    }

    @Test func tidakEligible() async {
        let gate = NFCGate(capabilities: FakeNFCCapabilities(cardSessionEligible: false), entitled: true)
        #expect(await gate.availability(.nfcHCE, config: config) == .notEligible)
    }

    @Test func seTidakEligible() async {
        let gate = NFCGate(capabilities: FakeNFCCapabilities(credentialSessionEligible: false), entitled: true)
        #expect(await gate.availability(.nfcSE, config: config) == .notEligible)
    }

    @Test func semuaLolos() async {
        let gate = NFCGate(capabilities: FakeNFCCapabilities(), entitled: true)
        #expect(await gate.availability(.nfcHCE, config: config) == .available)
        #expect(await gate.availability(.nfcSE, config: config) == .available)
    }

    @Test func tanpaEntitlementTidakMenyentuhCardSession() async {
        // Temuan review I8: build tanpa entitlement tidak boleh memanggil API CardSession sama sekali.
        let caps = FakeNFCCapabilities()
        let gate = NFCGate(capabilities: caps, entitled: false)
        #expect(await gate.availability(.nfcHCE, config: config) == .entitlementMissing)
        #expect(await gate.availability(.nfcSE, config: config) == .entitlementMissing)
        #expect(caps.calls.names.isEmpty)
        var factoryCalled = false
        await #expect(throws: ANError.channelUnavailable(.entitlementMissing)) {
            try await gate.withEligibleSession(.nfcHCE, config: config) { factoryCalled = true }
        }
        #expect(!factoryCalled)
    }

    @Test func sesiHanyaDibuatSetelahGatingLolos() async throws {
        let gate = NFCGate(capabilities: FakeNFCCapabilities(cardSessionEligible: false), entitled: true)
        var factoryCalled = false
        await #expect(throws: ANError.channelUnavailable(.notEligible)) {
            try await gate.withEligibleSession(.nfcHCE, config: config) { factoryCalled = true }
        }
        #expect(!factoryCalled)
    }
}

@Suite("Batas presentment (CLAUDE.md aturan 4)")
struct PresentmentBudgetTests {
    @Test func batasHCE() {
        #expect(PresentmentLimits.hceCooldownSeconds == 15)
        #expect(PresentmentLimits.hceEmulationSeconds == 60)
    }

    @Test func seDuaPerDelapanPuluhDetik() {
        var budget = SEAssertionBudget()
        let results = [0, 10, 79, 80.1].map { budget.tryAcquire(now: $0) }
        #expect(results == [true, true, false, true])
    }
}

import ANCore
import Testing
@testable import ANChannelBLE

@Suite("Ketersediaan kanal B (SDD §5.4)")
struct BLEAvailabilityTests {
    let config = RemoteConfig(enabledChannels: [.ble])

    @Test func diblokirServer() {
        #expect(BLEGate.availability(authorization: .allowed, poweredOn: true, config: RemoteConfig(enabledChannels: [])) == .regionBlocked)
    }

    @Test(arguments: [BLEAuthorization.denied, .restricted])
    func tidakDiizinkan(auth: BLEAuthorization) {
        #expect(BLEGate.availability(authorization: auth, poweredOn: true, config: config) == .bluetoothUnauthorized)
    }

    @Test func bluetoothMati() {
        #expect(BLEGate.availability(authorization: .allowed, poweredOn: false, config: config) == .bluetoothOff)
    }

    @Test func belumDitanyaTetapTersedia() {
        #expect(BLEGate.availability(authorization: .notDetermined, poweredOn: true, config: config) == .available)
    }
}

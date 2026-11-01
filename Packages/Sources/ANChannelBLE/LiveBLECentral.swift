@preconcurrency import CoreBluetooth
import Foundation

/// Central live di atas `CBCentralManager`. Semua callback Core Bluetooth dan
/// semua state internal hanya disentuh di `queue`.
public final class LiveBLECentral: NSObject, BLECentral, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.anastrophe.ble")
    private var manager: CBCentralManager!
    private var discovered: [UUID: (peripheral: CBPeripheral, advertisement: BLEReaderAdvertisement)] = [:]
    private var scanWindow: ScanWindow?
    private var scanStart = ContinuousClock.now
    private var powerWaiters: [CheckedContinuation<Void, any Error>] = []
    /// Per peripheral: token panggilan connect + continuation-nya.
    private var connectWaiters: [UUID: (token: UUID, waiter: CheckedContinuation<Void, any Error>)] = [:]
    /// Token connect yang dibatalkan sebelum sempat terdaftar.
    private var cancelledConnects: Set<UUID> = []
    private var links: [UUID: LiveBLELink] = [:]

    /// Membuat `CBCentralManager` memicu prompt izin Bluetooth, jadi buat saat pengguna
    /// pertama kali memakai kanal B (FR-82).
    public override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue)
    }

    /// `true`/`false` setelah state radio diketahui; `nil` selama belum diketahui.
    public var isPoweredOn: Bool? {
        queue.sync {
            switch manager.state {
            case .poweredOn: true
            case .unknown, .resetting: nil
            default: false
            }
        }
    }

    public func scan(_ window: ScanWindow) async throws -> [BLEReaderAdvertisement] {
        try await waitUntilPoweredOn()
        let start = ContinuousClock.now
        queue.sync {
            discovered = [:]
            scanWindow = window
            scanStart = start
            manager.scanForPeripherals(withServices: [BLEUUIDs.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        defer {
            queue.sync {
                manager.stopScan()
                scanWindow = nil
            }
        }
        while true {
            try await Task.sleep(for: .milliseconds(50))
            let (stop, state) = queue.sync { (scanWindow?.shouldStop(elapsed: ContinuousClock.now - start) ?? true, manager.state) }
            guard state == .poweredOn else { throw Self.error(for: state) }
            if stop { break }
        }
        return queue.sync { discovered.values.map(\.advertisement) }
    }

    public func connect(_ id: UUID) async throws -> any BLELink {
        guard let peripheral = queue.sync(execute: { discovered[id]?.peripheral }) else { throw BLEError.readerNotFound }
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
                queue.async { [self] in
                    if cancelledConnects.remove(token) != nil { return waiter.resume(throwing: CancellationError()) }
                    // Connect lama ke peripheral yang sama tidak boleh tertinggal tanpa jawaban.
                    connectWaiters[id]?.waiter.resume(throwing: CancellationError())
                    connectWaiters[id] = (token, waiter)
                    manager.connect(peripheral)
                }
            }
        } onCancel: { [self] in
            queue.async { [self] in
                guard let pending = connectWaiters[id], pending.token == token else {
                    cancelledConnects.insert(token)
                    return
                }
                connectWaiters[id] = nil
                manager.cancelPeripheralConnection(peripheral)
                pending.waiter.resume(throwing: CancellationError())
            }
        }
        let manager = manager!
        let link = LiveBLELink(peripheral: peripheral, queue: queue) { [queue] in
            queue.async { manager.cancelPeripheralConnection(peripheral) }
        }
        queue.sync { links[id] = link }
        do {
            try await link.prepare()
        } catch {
            await link.disconnect()
            throw error
        }
        return link
    }

    private func waitUntilPoweredOn() async throws {
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                switch manager.state {
                case .poweredOn: waiter.resume()
                case .unknown, .resetting: powerWaiters.append(waiter)
                default: waiter.resume(throwing: Self.error(for: manager.state))
                }
            }
        }
    }

    fileprivate static func error(for state: CBManagerState) -> BLEError {
        switch state {
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        default: .unsupported
        }
    }
}

extension LiveBLECentral: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let waiters = powerWaiters
        powerWaiters = []
        switch central.state {
        case .poweredOn:
            waiters.forEach { $0.resume() }
        case .unknown, .resetting:
            powerWaiters = waiters
        default:
            let error = Self.error(for: central.state)
            waiters.forEach { $0.resume(throwing: error) }
            connectWaiters.values.forEach { $0.waiter.resume(throwing: error) }
            connectWaiters = [:]
            links.values.forEach { $0.didDisconnect(error) }  // Bluetooth dimatikan di tengah transaksi
            links = [:]
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let groupID = serviceData[BLEUUIDs.service], groupID.count == 8,
              rssi.intValue != 127  // 127 = RSSI tidak tersedia
        else { return }
        scanWindow?.record(rssi: rssi.intValue, at: ContinuousClock.now - scanStart)
        // Nilai terkuat selama jendela pindai: pengguna mendekatkan iPhone saat memindai.
        let strongest = max(discovered[peripheral.identifier]?.advertisement.rssi ?? .min, rssi.intValue)
        discovered[peripheral.identifier] = (peripheral, BLEReaderAdvertisement(id: peripheral.identifier, groupID: groupID, rssi: strongest))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectWaiters.removeValue(forKey: peripheral.identifier)?.waiter.resume()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        connectWaiters.removeValue(forKey: peripheral.identifier)?.waiter.resume(throwing: error ?? BLEError.disconnected)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        connectWaiters.removeValue(forKey: peripheral.identifier)?.waiter.resume(throwing: BLEError.disconnected)
        links.removeValue(forKey: peripheral.identifier)?.didDisconnect(.disconnected)
    }
}

/// Link GATT ke satu reader. State hanya disentuh di `queue` milik central.
final class LiveBLELink: NSObject, BLELink, @unchecked Sendable {
    let commands: AsyncThrowingStream<Data, any Error>
    private let commandSink: AsyncThrowingStream<Data, any Error>.Continuation
    private let peripheral: CBPeripheral
    private let queue: DispatchQueue
    private let cancelConnection: @Sendable () -> Void
    private var control: CBCharacteristic?
    private var prepareWaiter: CheckedContinuation<Void, any Error>?
    private var writeWaiter: CheckedContinuation<Void, any Error>?
    /// Link sudah putus atau persiapannya dibatalkan.
    private var closedError: BLEError?

    init(peripheral: CBPeripheral, queue: DispatchQueue, cancelConnection: @escaping @Sendable () -> Void) {
        (commands, commandSink) = AsyncThrowingStream.makeStream(of: Data.self)
        self.peripheral = peripheral
        self.queue = queue
        self.cancelConnection = cancelConnection
        super.init()
    }

    /// ATT MTU − 3. Panjang `.withResponse` bisa 512 B (long write/Prepare-Execute) yang belum
    /// tentu didukung reader, jadi frame dipotong sesuai MTU yang dinegosiasikan.
    var mtu: Int {
        queue.sync { peripheral.maximumWriteValueLength(for: .withoutResponse) }
    }

    /// Menemukan service & karakteristik ANP lalu berlangganan indikasi `ANP-Response`.
    /// Pembatalan task memutus koneksi sehingga persiapan berakhir dengan error.
    func prepare() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
                queue.async { [self] in
                    if let closedError { return waiter.resume(throwing: closedError) }
                    prepareWaiter = waiter
                    peripheral.delegate = self
                    peripheral.discoverServices([BLEUUIDs.service])
                }
            }
        } onCancel: { [self] in
            queue.async { [self] in
                didDisconnect(.disconnected)
                cancelConnection()
            }
        }
    }

    func write(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                if let closedError { return waiter.resume(throwing: closedError) }
                guard let control else { return waiter.resume(throwing: BLEError.gattMismatch) }
                writeWaiter = waiter
                peripheral.writeValue(frame, for: control, type: .withResponse)
            }
        }
    }

    func disconnect() async {
        cancelConnection()
    }

    /// Dipanggil di `queue` saat koneksi putus atau Bluetooth dimatikan.
    func didDisconnect(_ error: BLEError) {
        guard closedError == nil else { return }
        closedError = error
        prepareWaiter?.resume(throwing: error)
        prepareWaiter = nil
        writeWaiter?.resume(throwing: error)
        writeWaiter = nil
        commandSink.finish(throwing: error)
    }

    private func failPreparation(_ error: (any Error)?) {
        prepareWaiter?.resume(throwing: error ?? BLEError.gattMismatch)
        prepareWaiter = nil
    }
}

extension LiveBLELink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BLEUUIDs.service }) else {
            return failPreparation(error)
        }
        peripheral.discoverCharacteristics([BLEUUIDs.control, BLEUUIDs.response], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        let characteristics = service.characteristics ?? []
        guard error == nil,
              let control = characteristics.first(where: { $0.uuid == BLEUUIDs.control }),
              let response = characteristics.first(where: { $0.uuid == BLEUUIDs.response })
        else { return failPreparation(error) }
        self.control = control
        peripheral.setNotifyValue(true, for: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == BLEUUIDs.response else { return }
        if let error { return failPreparation(error) }
        prepareWaiter?.resume()
        prepareWaiter = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == BLEUUIDs.response, error == nil, let value = characteristic.value else { return }
        commandSink.yield(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let waiter = writeWaiter
        writeWaiter = nil
        if let error { waiter?.resume(throwing: error) } else { waiter?.resume() }
    }
}

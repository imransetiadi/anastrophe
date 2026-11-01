import Foundation
import Network

/// Status koneksi internet untuk peringatan perpanjangan (TC-DEV-10).
public protocol ConnectivityStatus: Sendable {
    var isOnline: Bool { get }
}

/// Nilai tetap untuk preview, demo, dan test.
struct FixedConnectivity: ConnectivityStatus {
    let isOnline: Bool
}

/// Status jalur terakhir dari `NWPathMonitor`; `onChange` dipanggil saat online/offline berubah.
final class LiveConnectivity: ConnectivityStatus, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true

    init(onChange: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let now = path.status == .satisfied
            let changed = lock.withLock {
                defer { online = now }
                return online != now
            }
            if changed { onChange() }
        }
        monitor.start(queue: DispatchQueue(label: "app.anastrophe.connectivity"))
    }

    deinit { monitor.cancel() }

    var isOnline: Bool { lock.withLock { online } }
}

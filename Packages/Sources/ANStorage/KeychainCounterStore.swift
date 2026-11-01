import ANCore
import ANCrypto
import Foundation

/// Counter monoton per kredensial (SDD §7.6). Nilai baru disimpan **sebelum**
/// dikembalikan, sehingga transaksi yang gagal tidak pernah membuat counter
/// terulang atau mundur (TC-PROTO-11).
public struct KeychainCounterStore: CounterStore {
    /// Satu kunci untuk semua instance dalam proses: dua store di atas Keychain
    /// yang sama tetap tidak boleh membagikan nilai yang sama.
    private static let lock = NSLock()
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    public func next(for credentialID: Data) throws -> UInt32 {
        try Self.lock.withLock {
            let key = "cred.counter.\(credentialID.hexString)"
            let current = try store.get(key).map { $0.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } } ?? 0
            guard current < UInt32.max else { throw ANError.internalError }
            let next = current + 1
            try store.set(withUnsafeBytes(of: next.bigEndian) { Data($0) }, for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
            return next
        }
    }
}

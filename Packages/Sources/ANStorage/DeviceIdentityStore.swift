import Foundation

/// Identitas perangkat untuk enrolment (ADR-0045): UUID v4 acak yang dibuat app. Server membuat baris
/// perangkat pada enrolment pertama. Id ini tidak pernah ditampilkan atau di-log (ADR-0041).
public protocol DeviceIdentityStore: Sendable {
    func deviceID() throws -> String
}

/// Keychain `afterFirstUnlockThisDeviceOnly`, sehingga id tidak pindah ke perangkat lain lewat backup
/// (FR-40). Item Keychain bisa bertahan setelah app dihapus, jadi penanda instalasi di kontainer app
/// (dikecualikan dari backup) menandai instalasi baru: tanpa penanda, id dibuat ulang (FR-43). Kalau tidak,
/// kartu yang sama setelah instal ulang dijawab `ENR-DUPLICATE` padahal kartunya sudah hilang dari app.
public final class KeychainDeviceIdentityStore: DeviceIdentityStore, @unchecked Sendable {
    static let key = "device-id"
    private let store: any SecretStore
    private let installMarker: URL
    private let lock = NSLock()

    public init(store: any SecretStore, installMarker: URL) {
        self.store = store
        self.installMarker = installMarker
    }

    public func deviceID() throws -> String {
        try lock.withLock {
            if !FileManager.default.fileExists(atPath: installMarker.path(percentEncoded: false)) {
                try store.delete(Self.key)
                try createMarker()
            }
            if let data = try store.get(Self.key), let id = String(data: data, encoding: .utf8), UUID(uuidString: id) != nil {
                return id
            }
            let id = UUID().uuidString.lowercased()
            try store.set(Data(id.utf8), for: Self.key, accessibility: .afterFirstUnlockThisDeviceOnly)
            return id
        }
    }

    private func createMarker() throws {
        try FileManager.default.createDirectory(at: installMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: installMarker, options: .atomic)
        var marker = installMarker
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try marker.setResourceValues(values)
    }
}

import ANCore
import Foundation

/// Kartu yang terdeteksi pembaca, hanya berisi identifier (ADR-0001: kartu fisik hanya bukti kepemilikan;
/// tidak ada pembacaan sektor, NDEF, autentikasi, atau penulisan).
public enum DetectedTag: Equatable, Sendable {
    /// MIFARE (Ultralight, Plus, DESFire) lewat ISO 14443A: UID 4/7/10 byte.
    case miFare(identifier: Data)
    /// ISO 7816 di atas ISO 14443; tipe A memakai UID, tipe B memakai PUPI.
    case iso7816(identifier: Data, typeA: Bool)
    /// ISO 15693 (vicinity): UID 8 byte, urutan byte seperti yang diberikan Core NFC (uji H, TC-ENR-14).
    case iso15693(identifier: Data)
    /// Jenis lain (mis. FeliCa, yang butuh daftar system code per gedung) belum didukung.
    case unsupported
}

/// Memetakan kartu terdeteksi ke identitas yang dicocokkan server dengan registri gedung (ADR-0031).
public enum CardIdentityMapper {
    /// nil bila jenis kartu tidak didukung atau panjang identifier tidak sah, sehingga alur menampilkan
    /// "Kartu tidak dapat dibaca" dan menawarkan undangan (FR-13).
    public static func identity(for tag: DetectedTag) -> CardIdentity? {
        switch tag {
        case .miFare(let identifier), .iso7816(let identifier, typeA: true):
            CardIdentity(technology: .iso14443a, identifier: identifier)
        case .iso15693(let identifier):
            CardIdentity(technology: .iso15693, identifier: identifier)
        case .iso7816(_, typeA: false), .unsupported:
            nil
        }
    }
}

import Foundation

/// Rahasia enrolment mentah (ADR-0040): 32 byte acak per enrolment, hanya di memori selama alur
/// enrolment. Dikirim sebagai bearer saat kredensial pertama diprovisikan.
///
/// Tipe nominal terpisah dari `ProvisioningSecretHash` — bukan `Data` polos untuk keduanya — supaya
/// rahasia mentah dan hash-nya tidak bisa tertukar di pemanggil (mis. terbalik antara header
/// `Authorization` dan field `provisioning_key_hash`) tanpa galat kompilasi (ADR-0061). Pembuatan dan
/// hashing nyata (butuh `Security`/`CryptoKit`) ada di `ANStorage.ProvisioningSecretGenerator`; tipe
/// ini murni domain value tanpa I/O, agar bisa dipakai di `ANNetworking` tanpa menambah dependensi ke
/// `ANStorage`.
public struct ProvisioningSecret: Equatable, Sendable {
    public let raw: Data

    public init(raw: Data) {
        self.raw = raw
    }
}

/// SHA-256 dari `ProvisioningSecret`, dikirim ke server sebagai `provisioning_key_hash` saat enrolment
/// (ADR-0040). Tipe terpisah dari `ProvisioningSecret` — lihat dokumentasi di sana.
public struct ProvisioningSecretHash: Equatable, Sendable {
    public let raw: Data

    public init(raw: Data) {
        self.raw = raw
    }
}

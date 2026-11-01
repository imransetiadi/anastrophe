import ANCore
import Foundation

/// Hasil `POST /v1/enrollments/{id}/credentials` (FR-16). `Data` dikodekan base64,
/// tanggal ISO 8601. **Draf**: difinalkan di rencana backend (ADR-0014).
public struct ProvisionedCredential: Codable, Equatable, Sendable {
    public let credentialID: Data
    public let channel: ChannelKind
    /// `CredentialCert` CBOR (SDD §7.3).
    public let certificate: Data
    public let notAfter: Date
    /// Awal masa berlaku sertifikat; opsional agar respons lama tetap terbaca.
    public let notBefore: Date?
    public let siteName: String
    public let zones: [String]
    /// Hex `group_id` → [x963 aktif, x963 berikutnya].
    public let groupKeys: [String: [Data]]

    public init(credentialID: Data, channel: ChannelKind, certificate: Data, notAfter: Date, siteName: String, zones: [String], groupKeys: [String: [Data]], notBefore: Date? = nil) {
        self.credentialID = credentialID
        self.channel = channel
        self.certificate = certificate
        self.notAfter = notAfter
        self.notBefore = notBefore
        self.siteName = siteName
        self.zones = zones
        self.groupKeys = groupKeys
    }

    private enum CodingKeys: String, CodingKey {
        case credentialID = "credential_id"
        case channel
        case certificate
        case notAfter = "not_after"
        case notBefore = "not_before"
        case siteName = "site_name"
        case zones
        case groupKeys = "group_keys"
    }

    public static func decode(_ data: Data) throws -> ProvisionedCredential {
        try APIClient.decoder.decode(ProvisionedCredential.self, from: data)
    }
}

/// Nonce sekali pakai dari `POST /v1/credentials/{cred}:challenge` (FR-45, ADR-0023).
public struct RenewalChallenge: Decodable, Equatable, Sendable {
    public let nonce: Data
    public let expiresAt: Date

    public init(nonce: Data, expiresAt: Date) {
        self.nonce = nonce
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case nonce
        case expiresAt = "expires_at"
    }

    /// Pesan bukti kepemilikan yang ditandatangani kunci kredensial:
    /// `"ANP1-RENEW"` ‖ `cred_id` ‖ `nonce` (prefix memisahkan domain dari transcript ANP/1).
    public func message(credentialID: Data) -> Data {
        Data("ANP1-RENEW".utf8) + credentialID + nonce
    }
}

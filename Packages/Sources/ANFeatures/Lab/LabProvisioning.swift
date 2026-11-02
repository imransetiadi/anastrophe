#if DEBUG
import ANCore
import ANNetworking
import ANStorage
import Foundation

/// Provisioning kredensial lab untuk uji M1 tanpa backend (DEBUG saja; tidak ada
/// di build Release). Pasangannya: `scripts/anp1/lab_ca.py`.
///
/// 1. `begin` membuat kunci kredensial dan `cred_id`; tampilkan keduanya ke penguji.
/// 2. Penguji menjalankan `lab_ca.py issue --cred-id … --pubkey …`.
/// 3. `complete` mengimpor JSON hasilnya sebagai kartu aktif.
enum LabProvisioning {
    static func begin(keys: any CredentialKeyStore) throws -> (credentialID: Data, publicKey: Data) {
        try CardProvisioner.makeKey(keys: keys)
    }

    static func complete(json: Data, keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore) async throws -> Card {
        guard let provisioned = try? ProvisionedCredential.decode(json) else { throw ANError.invalidData }
        return try await CardProvisioner.store(provisioned, keys: keys, records: records, cards: cards)
    }

    /// Alur lab lewat backend dev (cmd/anastrophe-devseed + anastrophe-api): enrolment kartu terdaftar
    /// atau undangan (ADR-0033) dengan kanal yang dipilih penguji. Intinya sama dengan alur Tambah Kartu
    /// produksi (`CardProvisioner`); perangkat yang menunggu persetujuan dilaporkan sebagai galat.
    static func provisionViaBackend(
        api: APIClient,
        deviceID: String,
        siteID: String,
        card: CardIdentity,
        invitation: String? = nil,
        channel: ChannelKind,
        keys: any CredentialKeyStore,
        records: any CredentialRecordStore,
        cards: any CardStore,
        statusTokens: (any StatusTokenStore)? = nil
    ) async throws -> Card {
        let request: EnrollmentRequest = invitation.map { .invitation(token: $0) } ?? .card(siteID: siteID, identity: card)
        let outcome = try await CardProvisioner(api: api, keys: keys, records: records, cards: cards, statusTokens: statusTokens)
            .provision(request, deviceID: deviceID, channel: .fixed(channel))
        switch outcome {
        case .added(let card): return card
        case .pendingApproval: throw ANError.enrollmentRejected(.pendingApproval)
        }
    }
}
#endif

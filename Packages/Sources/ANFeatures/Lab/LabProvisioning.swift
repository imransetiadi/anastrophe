#if DEBUG
import ANCore
import ANNetworking
import ANStorage
import Foundation
import Security

/// Provisioning kredensial lab untuk uji M1 tanpa backend (DEBUG saja; tidak ada
/// di build Release). Pasangannya: `scripts/anp1/lab_ca.py`.
///
/// 1. `begin` membuat kunci kredensial dan `cred_id`; tampilkan keduanya ke penguji.
/// 2. Penguji menjalankan `lab_ca.py issue --cred-id … --pubkey …`.
/// 3. `complete` mengimpor JSON hasilnya sebagai kartu aktif.
enum LabProvisioning {
    static func begin(keys: any CredentialKeyStore) throws -> (credentialID: Data, publicKey: Data) {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ANError.internalError }
        let credentialID = Data(bytes)
        return (credentialID, try keys.createKey(for: credentialID))
    }

    static func complete(json: Data, keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore) async throws -> Card {
        guard let provisioned = try? ProvisionedCredential.decode(json) else { throw ANError.invalidData }
        return try await store(provisioned, keys: keys, records: records, cards: cards)
    }

    /// Alur lab lewat backend dev (cmd/anastrophe-devseed + anastrophe-api): enrolment kartu terdaftar
    /// atau undangan (ADR-0033), provisioning kredensial, lalu kunci dipindah ke `cred_id` dari server.
    /// Gagal di mana pun tidak menyisakan kunci, record, atau kartu (FR-19).
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
        // Batas 8 kartu juga di app (CLAUDE.md aturan 8): jangan buat enrolment server yang
        // kartunya pasti ditolak penyimpanan lokal.
        try CardLimit.ensureCanAdd(currentCount: try await cards.all().count)
        // Kanal yang dimatikan backend ditolak sebelum enrolment: setiap enrolment memakai satu
        // dari 8 slot kartu perangkat di server, juga bila langkah berikutnya gagal.
        guard try await api.fetchConfig().enabledChannels.contains(channel) else {
            throw ANError.channelUnavailable(.regionBlocked)
        }
        let (localID, publicKey) = try begin(keys: keys)
        var movedTo: Data?
        do {
            let start: EnrollmentStart
            if let invitation {
                start = try await api.createEnrollment(deviceID: deviceID, invitation: invitation, idempotencyKey: UUID())
            } else {
                start = try await api.createEnrollment(deviceID: deviceID, siteID: siteID, card: card, idempotencyKey: UUID())
            }
            // ADR-0032: perangkat tambahan menunggu operator; tidak ada provisioning sampai disetujui.
            guard start.status == .provisioning else { throw ANError.enrollmentRejected(.pendingApproval) }
            let enrollmentID = start.enrollmentID
            // ADR-0037: token baca status dibuat di perangkat; server hanya menerima hash-nya.
            let statusToken = statusTokens == nil ? nil : try StatusToken.generate()
            let provisioned = try await api.submitCredentialKey(enrollmentID: enrollmentID, channel: channel, publicKey: publicKey,
                                                                statusTokenHash: statusToken.map(StatusToken.hash), idempotencyKey: UUID())
            guard provisioned.channel == channel else { throw ANError.invalidData }
            try keys.moveKey(from: localID, to: provisioned.credentialID)
            movedTo = provisioned.credentialID
            let stored = try await store(provisioned, keys: keys, records: records, cards: cards, renewalURL: api.baseURL, serverCardID: enrollmentID)
            // Token hanya untuk membaca status: gagal menyimpannya tidak menggagalkan kartu, dan
            // perpanjangan berikutnya membuat token baru.
            if let statusToken { try? statusTokens?.save(statusToken, forCard: enrollmentID) }
            return stored
        } catch {
            try? keys.deleteKey(for: localID)
            if let movedTo { try? keys.deleteKey(for: movedTo) }
            throw error
        }
    }

    private static func store(_ provisioned: ProvisionedCredential, keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore, renewalURL: URL? = nil, serverCardID: String? = nil) async throws -> Card {
        guard [.ble, .nfcHCE].contains(provisioned.channel),
              (try? keys.hasKey(for: provisioned.credentialID)) == true
        else { throw ANError.invalidData }
        let record = CredentialRecord(
            credentialID: provisioned.credentialID,
            certificate: provisioned.certificate,
            notAfter: provisioned.notAfter,
            groupKeys: provisioned.groupKeys,
            notBefore: provisioned.notBefore,
            renewalURL: renewalURL,
            serverCardID: serverCardID
        )
        _ = try record.material(suspended: false)  // kunci reader group harus valid
        let card = Card(
            id: UUID(),
            name: provisioned.siteName,
            siteName: provisioned.siteName,
            zones: provisioned.zones,
            status: .active,
            credentials: [provisioned.channel: provisioned.credentialID],
            notAfter: provisioned.notAfter
        )
        do {
            try await cards.add(card)
        } catch {
            try? keys.deleteKey(for: provisioned.credentialID)  // FR-19: tanpa kredensial yatim
            throw error
        }
        do {
            try records.save(record)
        } catch {
            try? await cards.remove(id: card.id)
            try? keys.deleteKey(for: provisioned.credentialID)
            throw error
        }
        return card
    }
}
#endif

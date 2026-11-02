import ANCore
import ANNetworking
import ANStorage
import Foundation
import Security

/// Permintaan enrolment dari alur Tambah Kartu: kartu fisik terdaftar di gedung (ADR-0031, ADR-0044)
/// atau undangan sekali pakai (ADR-0033). Identitas kartu hanya dipakai untuk satu permintaan dan tidak
/// pernah disimpan (CLAUDE.md aturan 6).
public enum EnrollmentRequest: Sendable {
    case card(siteID: String, identity: CardIdentity)
    case invitation(token: String)
}

/// Hasil enrolment: kartu aktif, atau perangkat tambahan yang menunggu persetujuan operator (ADR-0032).
public enum EnrollmentOutcome: Equatable, Sendable {
    case added(Card)
    case pendingApproval
}

/// Kanal kredensial: tetap (layar Lab) atau dipilih otomatis dari `/v1/config` dan kelayakan perangkat
/// (FR-05, SDD §4.2).
enum ChannelChoice: Sendable {
    case fixed(ChannelKind)
    /// `siteChannels`: kanal gedung yang sudah diketahui sebelum enrolment (lookup kode gedung, ADR-0049).
    case automatic([ChannelKind: ChannelAvailability], siteChannels: Set<ChannelKind>? = nil)
}

/// Enrolment, provisioning kredensial, lalu penyimpanan kartu. Kunci dipindah ke `cred_id` dari server.
/// Gagal di mana pun tidak menyisakan kunci, record, atau kartu (FR-19).
struct CardProvisioner {
    /// Kanal in-app R1 (ADR-0002): W dan N-SE belum bisa diprovisikan dari app.
    static let inAppChannels: Set<ChannelKind> = [.nfcHCE, .ble]

    let api: APIClient
    let keys: any CredentialKeyStore
    let records: any CredentialRecordStore
    let cards: any CardStore
    let statusTokens: (any StatusTokenStore)?

    /// Kanal terbaik yang bisa diprovisikan: diizinkan server, didukung app, dan tersedia di perangkat.
    /// Untuk B, Bluetooth mati atau belum diizinkan tidak menghalangi provisioning; presentasi yang memberi
    /// panduan (FR-82).
    static func provisionableChannel(enabled: Set<ChannelKind>, availability: [ChannelKind: ChannelAvailability]) -> ChannelKind? {
        var provisionable = availability
        if [.bluetoothOff, .bluetoothUnauthorized].contains(availability[.ble]) { provisionable[.ble] = .available }
        return ChannelSelector.preferred(allowedBySite: enabled.intersection(inAppChannels), availability: provisionable)
    }

    func provision(_ request: EnrollmentRequest, deviceID: String, channel choice: ChannelChoice) async throws -> EnrollmentOutcome {
        // Batas 8 kartu juga di app (CLAUDE.md aturan 8): jangan buat enrolment server yang kartunya pasti
        // ditolak penyimpanan lokal.
        try CardLimit.ensureCanAdd(currentCount: try await cards.all().count)
        // Kanal dipilih sebelum enrolment: setiap enrolment memakai satu dari 8 slot kartu perangkat di
        // server, juga bila langkah berikutnya gagal.
        let enabled = try await api.fetchConfig().enabledChannels
        var channel: ChannelKind
        switch choice {
        case .fixed(let fixed):
            guard enabled.contains(fixed) else { throw ANError.channelUnavailable(.regionBlocked) }
            channel = fixed
        case .automatic(let availability, let siteChannels):
            guard !enabled.intersection(Self.inAppChannels).isEmpty else { throw ANError.channelUnavailable(.regionBlocked) }
            channel = try Self.select(enabled: enabled, siteChannels: siteChannels, availability: availability)
        }
        let (localID, publicKey) = try Self.makeKey(keys: keys)
        var movedTo: Data?
        do {
            // ADR-0040: rahasia enrolment hanya di memori selama alur ini; server menyimpan hash-nya.
            let secret = try ProvisioningSecret.generate()
            let secretHash = ProvisioningSecret.hash(secret)
            let start: EnrollmentStart
            switch request {
            case .invitation(let token):
                start = try await api.createEnrollment(deviceID: deviceID, invitation: token, provisioningKeyHash: secretHash, idempotencyKey: UUID())
            case .card(let siteID, let identity):
                start = try await api.createEnrollment(deviceID: deviceID, siteID: siteID, card: identity, provisioningKeyHash: secretHash, idempotencyKey: UUID())
            }
            // ADR-0032: perangkat tambahan menunggu operator; tidak ada provisioning sampai disetujui.
            guard start.status == .provisioning else {
                try? keys.deleteKey(for: localID)
                return .pendingApproval
            }
            // ADR-0049: respons enrolment membawa kanal gedung (satu-satunya sumber untuk jalur undangan).
            if case .automatic(let availability, _) = choice, let siteChannels = start.channels, !siteChannels.contains(channel) {
                channel = try Self.select(enabled: enabled, siteChannels: siteChannels, availability: availability)
            }
            let enrollmentID = start.enrollmentID
            // ADR-0037: token baca status dibuat di perangkat; server hanya menerima hash-nya dan hanya
            // memasangnya bila belum ada, jadi token yang sudah ada untuk instance ini dipakai ulang.
            var statusToken: Data?
            if let statusTokens {
                statusToken = try (try? statusTokens.token(forCard: enrollmentID)) ?? StatusToken.generate()
            }
            let provisioned = try await api.submitCredentialKey(enrollmentID: enrollmentID, channel: channel, publicKey: publicKey,
                                                                statusTokenHash: statusToken.map(StatusToken.hash), provisioningSecret: secret, idempotencyKey: UUID())
            guard provisioned.channel == channel else { throw ANError.invalidData }
            try keys.moveKey(from: localID, to: provisioned.credentialID)
            movedTo = provisioned.credentialID
            let stored = try await Self.store(provisioned, keys: keys, records: records, cards: cards, renewalURL: api.baseURL, serverCardID: enrollmentID)
            // Token hanya untuk membaca status: gagal menyimpannya tidak menggagalkan kartu, dan
            // perpanjangan berikutnya membuat token baru.
            if let statusToken { try? statusTokens?.save(statusToken, forCard: enrollmentID) }
            return .added(stored)
        } catch {
            try? keys.deleteKey(for: localID)
            if let movedTo { try? keys.deleteKey(for: movedTo) }
            throw error
        }
    }

    /// Kanal terbaik dari kanal global ∩ kanal gedung. Bila kanal gedung tidak bisa dipakai tetapi kanal
    /// global bisa, galatnya menjelaskan batasan dari gedung: iPhone hanya disalahkan bila setiap kanal yang
    /// diizinkan terhalang oleh perangkat itu sendiri (review akhir kebijakan gedung).
    static func select(enabled: Set<ChannelKind>, siteChannels: Set<ChannelKind>?, availability: [ChannelKind: ChannelAvailability]) throws -> ChannelKind {
        let allowed = siteChannels.map { enabled.intersection($0) } ?? enabled
        if let selected = provisionableChannel(enabled: allowed, availability: availability) { return selected }
        guard siteChannels != nil, provisionableChannel(enabled: enabled, availability: availability) != nil else {
            throw ANError.channelUnavailable(.notEligible)
        }
        let allowedInApp = allowed.intersection(inAppChannels)
        let deviceCauses: Set<ChannelAvailability> = [.unsupportedDevice, .notEligible]
        if !allowedInApp.isEmpty, allowedInApp.allSatisfy({ deviceCauses.contains(availability[$0] ?? .notEligible) }) {
            throw ANError.siteChannelUnavailable
        }
        throw ANError.siteChannelsNotOffered
    }

    /// Kunci kredensial baru dengan `cred_id` lokal sementara (16 byte acak).
    static func makeKey(keys: any CredentialKeyStore) throws -> (credentialID: Data, publicKey: Data) {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ANError.internalError }
        let credentialID = Data(bytes)
        return (credentialID, try keys.createKey(for: credentialID))
    }

    /// Menyimpan kredensial yang sudah diprovisikan sebagai kartu aktif beserta record-nya.
    static func store(_ provisioned: ProvisionedCredential, keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore,
                      renewalURL: URL? = nil, serverCardID: String? = nil) async throws -> Card {
        guard inAppChannels.contains(provisioned.channel),
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

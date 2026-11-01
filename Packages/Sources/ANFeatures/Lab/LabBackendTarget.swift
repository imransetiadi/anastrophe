#if DEBUG
import ANCore
import ANCrypto
import ANNetworking
import Foundation
import LocalAuthentication

/// Backend dev untuk provisioning lab (`cmd/anastrophe-devseed` + `anastrophe-api`). DEBUG saja.
struct LabBackendTarget: Equatable, Sendable {
    let baseURL: URL
    let deviceID: String
    let siteID: String

    /// Isian form lab; nil bila URL bukan http(s) dengan host atau salah satu ID kosong.
    init?(url: String, deviceID: String, siteID: String) {
        func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let baseURL = URL(string: trimmed(url)),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host() != nil,
              !trimmed(deviceID).isEmpty, !trimmed(siteID).isEmpty
        else { return nil }
        self.baseURL = baseURL
        self.deviceID = trimmed(deviceID)
        self.siteID = trimmed(siteID)
    }

    /// `-ANLabBackend <url> -ANLabDevice <id> -ANLabSite <id>`; nil bila salah satu tidak ada.
    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
                  !arguments[index + 1].hasPrefix("-")
            else { return nil }
            return arguments[index + 1]
        }
        guard let url = value("-ANLabBackend"), let device = value("-ANLabDevice"), let site = value("-ANLabSite") else { return nil }
        self.init(url: url, deviceID: device, siteID: site)
    }
}

extension AppServices {
    /// Membaca argumen peluncuran lab; provisioning berjalan saat layar Kunci pertama tampil.
    public func configureLabBackend(arguments: [String]) {
        pendingLabBackend = LabBackendTarget(arguments: arguments)
        pendingLabRenewal = arguments.contains("-ANLabRenew")
    }

    /// Perpanjangan dari `-ANLabRenew`, sekali per peluncuran; nil bila tidak diminta.
    func runPendingLabRenewal(transport: any HTTPTransport = URLSession.shared) async -> String? {
        guard pendingLabRenewal else { return nil }
        pendingLabRenewal = false
        guard let card = try? await cards.all().first(where: { $0.credentials[.ble] != nil || $0.credentials[.nfcHCE] != nil }) else { return nil }
        return await labRenew(card: card, transport: transport)
    }

    /// Memperpanjang sertifikat kartu tanpa menunggu tap (lab). Di simulator kunci perangkat
    /// lunak tidak memakai konteks; di iPhone konteks baru memunculkan Face ID/passcode.
    func labRenew(card: Card, transport: any HTTPTransport = URLSession.shared) async -> String {
        guard let channel = [ChannelKind.ble, .nfcHCE].first(where: { card.credentials[$0] != nil }) else {
            return localized("lab.renew_failed")
        }
        do {
            _ = try await CredentialRenewer(keys: keys, records: records, cards: cards, transport: transport)
                .renew(card: card, channel: channel, context: AuthorizedContext(laContext: LAContext()))
            return localized("lab.renewed")
        } catch let problem as ProblemDetails {
            return "\(localized("lab.renew_failed")) (\(problem.type))"
        } catch {
            return localized("lab.renew_failed")
        }
    }

    /// Provisioning lab dari argumen peluncuran, sekali per peluncuran; nil bila tidak ada.
    func runPendingLabBackendProvisioning(transport: any HTTPTransport = URLSession.shared) async -> String? {
        guard let target = pendingLabBackend else { return nil }
        pendingLabBackend = nil
        // Tanpa penyimpanan, kartu dari server pasti ditolak lokal dan slot server terbuang.
        guard !storageFailed else { return nil }
        // Argumen skema Xcode bertahan antar-Run: hanya perangkat tanpa kartu yang diprovisikan
        // otomatis. Kartu berikutnya lewat layar Lab.
        if let existing = try? await cards.all(), !existing.isEmpty { return localized("lab.backend.skipped") }
        return await provisionFromLabBackend(target, channel: .ble, transport: transport)
    }

    /// Mengambil kartu dari backend dev; mengembalikan pesan untuk penguji.
    func provisionFromLabBackend(_ target: LabBackendTarget, channel: ChannelKind, transport: any HTTPTransport = URLSession.shared) async -> String {
        do {
            _ = try await LabProvisioning.provisionViaBackend(
                api: APIClient(baseURL: target.baseURL, transport: transport),
                deviceID: target.deviceID, siteID: target.siteID, channel: channel,
                keys: keys, records: records, cards: cards
            )
            return localized("lab.imported")
        } catch ANError.cardLimitReached {
            return localized("lab.limit")
        } catch ANError.channelUnavailable {
            return localized("lab.backend.channel_disabled")
        } catch let problem as ProblemDetails {
            return "\(localized("lab.backend.failed")) (\(problem.type))"
        } catch {
            return localized("lab.backend.failed")
        }
    }
}
#endif

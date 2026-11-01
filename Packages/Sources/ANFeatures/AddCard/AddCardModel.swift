import ANCore
import ANNetworking
import ANNFCEnroll
import Foundation
import Observation

/// Cara alur Tambah Kartu dibuka: dari tombol (pilih cara), atau dari tautan undangan yang dibuka sistem
/// (`onOpenURL`). Hanya `https://<host>/i/<token>`; tidak ada skema URL kustom karena token sekali pakai
/// bisa disadap app lain.
public enum AddCardEntry: Identifiable, Equatable, Sendable {
    case start
    case invitation(URL)

    public var id: String {
        switch self {
        case .start: "start"
        case .invitation: "invitation"
        }
    }

    public static func entry(for url: URL) -> AddCardEntry? {
        InvitationLink.token(from: url) == nil ? nil : .invitation(url)
    }
}

/// Langkah alur Tambah Kartu produksi (FR-10–FR-13, ADR-0043): kode gedung → konfirmasi gedung → tempel
/// kartu, atau tautan undangan. Identitas kartu hanya hidup di dalam satu pemanggilan dan tidak pernah
/// masuk state (CLAUDE.md aturan 6).
@MainActor
@Observable
public final class AddCardModel {
    public enum Step: Equatable {
        case chooseMethod
        case siteCode
        case confirmSite(SiteSummary)
        case invitation
        case working
        case done(Card)
        case pending(siteName: String?)
        case failed(Failure)
    }

    public struct Failure: Equatable, Sendable {
        public let message: String
        /// FR-13: kartu tak terdaftar atau tak terbaca → tawarkan jalur undangan.
        public let offersInvitation: Bool
    }

    public internal(set) var step: Step = .chooseMethod
    public var codeInput = ""
    public var linkInput = ""
    public private(set) var fieldError: String?
    /// Permintaan sedang berjalan: tombol aksi nonaktif dan ketukan kedua diabaikan (Review Focus 4).
    public private(set) var isBusy = false

    private let services: AppServices
    private let reader: any CardOwnershipReader
    private let transport: any HTTPTransport
    /// Gedung terakhir yang dikonfirmasi, agar "Coba lagi" setelah gagal membaca kartu tidak meminta kode lagi.
    private var confirmedSite: SiteSummary?

    init(services: AppServices, reader: any CardOwnershipReader, transport: any HTTPTransport = URLSession.shared) {
        self.services = services
        self.reader = reader
        self.transport = transport
    }

    /// Build tanpa alamat layanan tidak bisa menambah kartu.
    public var isServiceAvailable: Bool { services.apiBaseURL != nil }

    public func chooseCard() {
        fieldError = nil
        step = .siteCode
    }

    public func chooseInvitation() {
        fieldError = nil
        confirmedSite = nil
        step = .invitation
    }

    /// Tautan undangan yang dibuka sistem hanya mengisi field. Enrolment tetap menunggu pengguna mengetuk
    /// "Tambahkan kartu", sehingga tautan kiriman orang lain tidak mendaftarkan kartu diam-diam.
    public func prefill(invitationURL: URL) {
        chooseInvitation()
        linkInput = invitationURL.absoluteString
    }

    /// Mundur satu langkah. Dari hasil gagal kembali ke gedung yang sudah dikonfirmasi (jalur kartu), atau
    /// ke pilihan cara.
    public func back() {
        guard !isBusy else { return }
        fieldError = nil
        switch step {
        case .confirmSite: step = .siteCode
        case .failed: step = confirmedSite.map { .confirmSite($0) } ?? .chooseMethod
        case .siteCode, .invitation: step = .chooseMethod
        default: break
        }
    }

    /// Mencari gedung dari kode yang diketik. Kode tidak berbentuk sah ditolak tanpa jaringan; galat
    /// ditampilkan di dekat field.
    public func submitCode() async {
        guard !isBusy else { return }
        guard let api = api() else { return }
        guard SiteJoinCode.normalized(codeInput) != nil else {
            fieldError = localized("add.code.invalid")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let site = try await api.lookupSite(code: codeInput)
            fieldError = nil
            confirmedSite = site
            step = .confirmSite(site)
        } catch {
            fieldError = Self.failure(for: error).message
        }
    }

    /// Membaca kartu fisik lalu mendaftarkannya ke gedung yang dikonfirmasi. Pembatalan kembali ke
    /// konfirmasi tanpa pesan.
    public func confirmAndRead() async {
        guard !isBusy, case .confirmSite(let site) = step else { return }
        guard let api = api() else { return }
        isBusy = true
        defer { isBusy = false }
        let identity: CardIdentity
        do {
            identity = try await reader.readIdentity()
        } catch is CancellationError {
            return
        } catch {
            step = .failed(Self.failure(for: error))
            return
        }
        step = .working
        await enroll(.card(siteID: site.siteID, identity: identity), api: api, siteName: site.name, siteChannels: site.channels)
    }

    public func submitInvitation() async {
        guard !isBusy else { return }
        guard let url = URL(string: linkInput.trimmingCharacters(in: .whitespacesAndNewlines)), let token = InvitationLink.token(from: url) else {
            fieldError = localized("add.link.invalid")
            return
        }
        await startInvitation(token: token)
    }

    /// Enrolment dengan token undangan, dari field tautan atau dari tautan yang dibuka sistem.
    public func startInvitation(token: String) async {
        guard !isBusy else { return }
        guard let api = api() else { return }
        isBusy = true
        defer { isBusy = false }
        fieldError = nil
        step = .working
        await enroll(.invitation(token: token), api: api, siteName: nil, siteChannels: nil)
    }

    private func enroll(_ request: EnrollmentRequest, api: APIClient, siteName: String?, siteChannels: Set<ChannelKind>?) async {
        do {
            let deviceID = try services.deviceIdentity.deviceID()
            let availability = await services.availability()
            let outcome = try await CardProvisioner(api: api, keys: services.keys, records: services.records, cards: services.cards, statusTokens: services.statusTokens)
                .provision(request, deviceID: deviceID, channel: .automatic(availability, siteChannels: siteChannels))
            switch outcome {
            case .added(let card):
                step = .done(card)
                services.cardsRevision.bump()
            case .pendingApproval:
                step = .pending(siteName: siteName)
            }
        } catch {
            step = .failed(Self.failure(for: error))
        }
    }

    /// Klien API, atau langkah gagal "layanan belum tersedia" bila build tanpa alamat layanan.
    private func api() -> APIClient? {
        guard let baseURL = services.apiBaseURL else {
            step = .failed(Self.failure(for: ANError.serviceUnavailable))
            return nil
        }
        return APIClient(baseURL: baseURL, transport: transport)
    }

    static func failure(for error: any Error) -> Failure {
        // FR-13: kartu tak terdaftar, tak terbaca, perangkat tanpa pembaca, atau gedung yang belum memakai
        // registri kartu (hanya undangan, review akhir #7) → tawarkan jalur undangan.
        let offersInvitation = switch error as? ANError {
        case .enrollmentRejected(.notRegistered)?, .enrollmentRejected(.siteUnsupported)?, .cardUnreadable?, .cardReaderUnavailable?: true
        default: false
        }
        if let text = EnrollmentMessages.text(for: error) { return Failure(message: text, offersInvitation: offersInvitation) }
        if error is URLError { return Failure(message: localized("add.error.offline"), offersInvitation: false) }
        return Failure(message: localized("add.error.generic"), offersInvitation: false)
    }
}

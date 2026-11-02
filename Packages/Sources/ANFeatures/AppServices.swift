import ANChannelBLE
import ANChannelNFC
import ANCore
import ANCrypto
import ANNetworking
import ANNFCEnroll
import ANProtocol
import ANStorage
import ANWallet
import Foundation
import LocalAuthentication
import SwiftUI

/// Status foreground app, dibaca coordinator BLE (ADR-0012) dan diperbarui dari `scenePhase`.
public final class ForegroundState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    public init() {}

    public var isActive: Bool {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }
}

/// Naik setiap kali data kartu berubah di luar layar Kunci (mis. perpanjangan sesudah tap),
/// agar daftar dimuat ulang.
@MainActor
@Observable
public final class CardsRevision {
    public private(set) var value = 0
    public init() {}
    func bump() { value += 1 }
}

/// Memulai dan membatalkan presentasi untuk kartu yang dipilih pengguna.
@MainActor
protocol PresentationLaunching: AnyObject {
    func start(card: Card, channel: ChannelKind) async -> AsyncStream<PresentmentEvent>
    func cancel() async
}

/// Composition root fitur. Target app hanya menautkan `ANFeatures`, jadi perakitan
/// implementasi live ada di sini; `App/AppEnvironment.swift` memilih varian.
@MainActor
public final class AppServices {
    let cards: any CardStore
    let keys: any CredentialKeyStore
    let records: any CredentialRecordStore
    let availability: @MainActor () async -> [ChannelKind: ChannelAvailability]
    let launcher: any PresentationLaunching
    public let foreground: ForegroundState
    public let cardsRevision: CardsRevision
    let connectivity: any ConnectivityStatus
    /// Autentikasi untuk aksi sensitif di luar presentasi (hapus kartu, FR-31).
    let authenticator: any UserAuthenticator
    /// Riwayat tap lokal 30 hari (FR-30).
    let tapHistory: any TapHistoryStore
    /// Token baca status kartu (ADR-0037), di Keychain yang sama dengan record kredensial.
    let statusTokens: any StatusTokenStore
    private let statusRefresher: CardStatusRefresher
    /// Alamat API enrolment dari Info.plist `ANAPIBaseURL` (nil = layanan belum tersedia).
    let apiBaseURL: URL?
    /// `device_id` untuk enrolment (ADR-0045).
    let deviceIdentity: any DeviceIdentityStore
    /// Store kartu tidak bisa dibuka; UI memberi tahu alih-alih menampilkan daftar kosong.
    public let storageFailed: Bool
    #if DEBUG
    /// Layar yang dibuka otomatis untuk verifikasi visual dan audit aksesibilitas (`-ANDemoScreen`, ADR-0057).
    public var demoScreen: DemoScreen?
    /// Provisioning lab yang menunggu layar Kunci (`-ANLabBackend`), lihat `LabBackendTarget`.
    var pendingLabBackend: LabBackendTarget?
    /// Perpanjangan lab saat peluncuran (`-ANLabRenew`) untuk verifikasi di simulator.
    var pendingLabRenewal = false
    /// Hapus kartu lab saat peluncuran (`-ANLabDelete`) untuk verifikasi di simulator.
    var pendingLabDelete = false
    /// Identitas kartu untuk pembaca palsu di simulator (`-ANLabCardReader`), karena simulator tidak bisa
    /// membaca kartu fisik.
    var labCardIdentity: CardIdentity?
    /// Tautan yang dibuka seperti `onOpenURL` saat peluncuran (`-ANLabOpenURL`).
    var pendingLabOpenURL: URL?
    /// Kode gedung untuk menjalankan alur Tambah Kartu otomatis saat peluncuran (`-ANLabAddCode`).
    var pendingLabAddCode: String?
    #endif

    init(
        cards: any CardStore,
        keys: any CredentialKeyStore,
        records: any CredentialRecordStore,
        availability: @escaping @MainActor () async -> [ChannelKind: ChannelAvailability],
        launcher: any PresentationLaunching,
        foreground: ForegroundState,
        cardsRevision: CardsRevision = CardsRevision(),
        connectivity: any ConnectivityStatus = FixedConnectivity(isOnline: true),
        authenticator: any UserAuthenticator,
        tapHistory: any TapHistoryStore,
        statusTokens: any StatusTokenStore = KeychainStatusTokenStore(store: InMemorySecretStore()),
        storageFailed: Bool = false,
        apiBaseURL: URL? = nil,
        deviceIdentity: any DeviceIdentityStore = KeychainDeviceIdentityStore(
            store: InMemorySecretStore(), installMarker: FileManager.default.temporaryDirectory.appending(path: "anastrophe-\(UUID().uuidString)/installed"))
    ) {
        self.cards = cards
        self.keys = keys
        self.records = records
        self.availability = availability
        self.launcher = launcher
        self.foreground = foreground
        self.cardsRevision = cardsRevision
        self.connectivity = connectivity
        self.authenticator = authenticator
        self.tapHistory = tapHistory
        self.statusTokens = statusTokens
        self.statusRefresher = CardStatusRefresher(cards: cards, records: records, tokens: statusTokens)
        self.storageFailed = storageFailed
        self.apiBaseURL = apiBaseURL
        self.deviceIdentity = deviceIdentity
    }

    /// Pembaca kartu fisik untuk alur Tambah Kartu (FR-11). Teks lembar sistem terlokalisasi tanpa istilah
    /// teknis.
    func makeCardReader() -> any CardOwnershipReader {
        #if DEBUG && targetEnvironment(simulator)
        if let labCardIdentity { return FixedCardOwnershipReader(.identity(labCardIdentity)) }
        #endif
        #if os(iOS) && canImport(CoreNFC)
        return NFCTagCardOwnershipReader(prompt: localized("add.read.prompt"), multipleCardsMessage: localized("add.read.multiple"))
        #else
        return FixedCardOwnershipReader(.failure(.cardReaderUnavailable))
        #endif
    }

    /// Dipakai bila `live()` gagal membuka penyimpanan: tidak ada presentasi, UI memberi tahu. Alamat layanan
    /// tetap diteruskan agar laporan diagnostik tidak salah menyebut layanan belum terkonfigurasi.
    public static func storageUnavailable(apiBaseURL: URL? = nil) -> AppServices {
        let secrets = InMemorySecretStore()
        return AppServices(
            cards: EmptyCardStore(),
            keys: DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory()),
            records: KeychainCredentialRecordStore(store: secrets),
            availability: { [:] },
            launcher: ScriptedPresentationLauncher(events: [.cancelled], finishes: true),
            foreground: ForegroundState(),
            authenticator: UnavailableAuthenticator(),
            tapHistory: InMemoryTapHistoryStore(),
            storageFailed: true,
            apiBaseURL: apiBaseURL
        )
    }

    /// Status kartu dari server saat app masuk foreground (FR-38, ADR-0037); true bila ada kartu yang
    /// berubah sehingga daftar perlu dimuat ulang.
    public func refreshCardStatuses(transport: any HTTPTransport = URLSession.shared) async -> Bool {
        guard !storageFailed else { return false }
        return await statusRefresher.refresh(transport: transport)
    }

    /// FR-43 (ADR-0053): pada peluncuran pertama sesudah instal ulang, sisa Keychain instalasi lama dihapus
    /// sebelum layanan dipakai. Store kartu yang gagal dibaca dianggap berisi kartu, jadi tidak ada yang
    /// dihapus. Galat penghapusan tidak menghentikan app; pembersihan dicoba lagi di peluncuran berikutnya
    /// selama belum ada enrolment (`deviceID()` membuat penanda saat enrolment).
    public func prepareInstall() async {
        let hasCards: Bool
        do {
            hasCards = try await !cards.all().isEmpty
        } catch {
            hasCards = true
        }
        _ = try? deviceIdentity.purgeLeftoversIfFreshInstall(hasCards: hasCards)
    }

    /// Membatalkan presentasi yang sedang berjalan (Review Focus 2).
    public func cancelPresentation() async {
        await launcher.cancel()
    }

    /// Presentasi hanya dibatalkan saat app benar-benar ke background (O-A18, ADR-0012).
    /// `.inactive` juga terjadi selama prompt Face ID/passcode, jadi tidak boleh membatalkan.
    public func handleScenePhase(_ phase: ScenePhase) async {
        foreground.isActive = phase != .background
        if phase == .background { await cancelPresentation() }
    }

    /// Kanal yang diizinkan selama backend `/config` belum ada (ADR-0014). N-HCE hanya
    /// bila build membawa entitlement emulasi (`AN_NFC_EMULATION`).
    static func localConfig(nfcEmulationEntitled: Bool) -> RemoteConfig {
        RemoteConfig(enabledChannels: nfcEmulationEntitled ? [.ble, .nfcHCE] : [.ble])
    }

    public static func live(nfcEmulationEntitled: Bool, apiBaseURL: URL? = nil) throws -> AppServices {
        let secrets = deviceSecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: keyFactory())
        let records = KeychainCredentialRecordStore(store: secrets)
        let foreground = ForegroundState()
        let config = localConfig(nfcEmulationEntitled: nfcEmulationEntitled)
        let cards = try SwiftDataCardStore(directory: URL.applicationSupportDirectory.appending(path: "Anastrophe/Cards"))
        let revision = CardsRevision()
        // ADR-0029: riwayat tidak pernah membuat kartu tak tersedia.
        let tapHistory = SwiftDataTapHistoryStore.openRecovering(directory: URL.applicationSupportDirectory.appending(path: "Anastrophe/TapHistory"))
        let statusTokens = KeychainStatusTokenStore(store: secrets)
        let launcher = LivePresentationLauncher(keys: keys, records: records, cards: cards, statusTokens: statusTokens, counters: KeychainCounterStore(store: secrets), foreground: foreground, config: config, nfcEmulationEntitled: nfcEmulationEntitled, onCardsChanged: { revision.bump() })
        return AppServices(
            cards: cards,
            keys: keys,
            records: records,
            availability: { await liveAvailability(config: config, nfcEmulationEntitled: nfcEmulationEntitled, bluetoothPoweredOn: launcher.bluetoothPoweredOn) },
            launcher: RecordingLauncher(base: launcher, history: tapHistory),
            foreground: foreground,
            cardsRevision: revision,
            connectivity: LiveConnectivity(onChange: { Task { @MainActor in revision.bump() } }),
            authenticator: LAUserAuthenticator(),
            tapHistory: tapHistory,
            statusTokens: statusTokens,
            apiBaseURL: apiBaseURL,
            // ADR-0045: penanda instalasi di kontainer app; hilang saat instal ulang sehingga id dibuat ulang.
            deviceIdentity: KeychainDeviceIdentityStore(store: secrets, installMarker: URL.applicationSupportDirectory.appending(path: "Anastrophe/installed"))
        )
    }

    /// Penyimpanan sementara tanpa data (preview dan cadangan bila store gagal dibuka).
    public static func inMemory() -> AppServices {
        inMemory(events: [.waitingForReader])
    }

    static func inMemory(events: [PresentmentEvent], connectivity: any ConnectivityStatus = FixedConnectivity(isOnline: true),
                         authenticator: any UserAuthenticator = ImmediateAuthenticator(), apiBaseURL: URL? = nil) -> AppServices {
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let directory = FileManager.default.temporaryDirectory.appending(path: "anastrophe-\(UUID().uuidString)")
        let tapHistory = InMemoryTapHistoryStore()
        return AppServices(
            cards: (try? SwiftDataCardStore(directory: directory)) ?? EmptyCardStore(),
            keys: keys,
            records: KeychainCredentialRecordStore(store: secrets),
            availability: { [.ble: .available, .nfcHCE: .notEligible] },
            launcher: RecordingLauncher(base: ScriptedPresentationLauncher(events: events), history: tapHistory),
            foreground: ForegroundState(),
            connectivity: connectivity,
            authenticator: authenticator,
            tapHistory: tapHistory,
            statusTokens: KeychainStatusTokenStore(store: secrets),
            apiBaseURL: apiBaseURL
        )
    }

    /// Hapus kartu (FR-31): autentikasi pengguna, cabut di server (ADR-0026), lalu hapus lokal.
    public func removeCard(_ card: Card) async throws {
        let remover = CardRemover(keys: keys, records: records, cards: cards, statusTokens: statusTokens)
        let hasKey = try card.credentials.values.contains { try keys.hasKey(for: $0) }
        var context: AuthorizedContext?
        do {
            context = try await authenticator.authenticate(reason: localized("detail.delete.auth_reason"))
        } catch let error as LAError where error.code == .passcodeNotSet && !hasKey {
            // ADR-0028: kartu tanpa kunci tidak bisa dipakai; tetap bisa dihapus tanpa passcode.
        }
        defer { context?.laContext.invalidate() }
        try await remover.remove(card: card, context: context)
        try? await tapHistory.removeAll(for: card.id)  // FR-30: riwayat ikut terhapus
    }

    private static func liveAvailability(config: RemoteConfig, nfcEmulationEntitled: Bool, bluetoothPoweredOn: Bool?) async -> [ChannelKind: ChannelAvailability] {
        var result: [ChannelKind: ChannelAvailability] = [
            // Status radio baru diketahui setelah central dibuat; sebelum itu anggap menyala
            // dan biarkan coordinator memberi panduan bila ternyata mati (FR-82).
            .ble: BLEGate.availability(authorization: .current, poweredOn: bluetoothPoweredOn ?? true, config: config),
            .wallet: WalletGate.availability(config: config),
        ]
        #if os(iOS)
        let gate = NFCGate(capabilities: LiveNFCCapabilities(), entitled: nfcEmulationEntitled)
        result[.nfcHCE] = await gate.availability(.nfcHCE, config: config)
        result[.nfcSE] = await gate.availability(.nfcSE, config: config)
        #endif
        return result
    }

    private static func keyFactory() -> any SigningKeyFactory {
        #if targetEnvironment(simulator)
        SoftwareKeyFactory()  // simulator tidak punya Secure Enclave
        #else
        SecureEnclaveKeyFactory()
        #endif
    }

    private static func deviceSecretStore() -> any SecretStore {
        #if targetEnvironment(simulator)
        SimulatorSecretStore(base: KeychainSecretStore())
        #else
        KeychainSecretStore()
        #endif
    }
}

#if targetEnvironment(simulator)
/// Simulator tidak punya passcode, sehingga item `WhenPasscodeSet` gagal disimpan.
/// Hanya di simulator: kelas proteksi diturunkan agar alur lab bisa dicoba.
private struct SimulatorSecretStore: SecretStore {
    let base: KeychainSecretStore

    func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws {
        try base.set(data, for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    func get(_ key: String) throws -> Data? { try base.get(key) }
    func delete(_ key: String) throws { try base.delete(key) }
    func deleteAll() throws { try base.deleteAll() }
}
#endif

/// Autentikasi yang selalu gagal (layanan tanpa penyimpanan: tidak ada yang bisa dihapus).
struct UnavailableAuthenticator: UserAuthenticator {
    func authenticate(reason: String) async throws -> AuthorizedContext { throw ANError.internalError }
}

/// Autentikasi langsung berhasil untuk preview, demo, dan penyimpanan sementara.
struct ImmediateAuthenticator: UserAuthenticator {
    func authenticate(reason: String) async throws -> AuthorizedContext {
        AuthorizedContext(laContext: LAContext())
    }
}

/// Kartu kosong bila SwiftData tidak bisa dibuka sama sekali.
private struct EmptyCardStore: CardStore {
    func all() async throws -> [Card] { [] }
    func add(_ card: Card) async throws { throw ANError.internalError }
    func update(_ card: Card) async throws {}
    func remove(id: UUID) async throws {}
}

/// Kartu & kanal yang sedang dipresentasikan, dibaca `makeProvider` di coordinator.
private final class Selection: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (card: Card, channel: ChannelKind, tap: UUID)?

    var current: (card: Card, channel: ChannelKind, tap: UUID)? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Merakit coordinator live. Satu coordinator BLE dipakai ulang agar rate-limit per
/// reader (3 dtk) tetap berlaku antar-tap.
@MainActor
private final class LivePresentationLauncher: PresentationLaunching {
    private let selection = Selection()
    private let makeProvider: @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider
    private let prepare: @Sendable (AuthorizedContext) async -> Void
    private let scheduler: RenewalScheduler<ContinuousClock>
    private let foreground: ForegroundState
    private let config: RemoteConfig
    private let nfcEmulationEntitled: Bool
    private var central: LiveBLECentral?
    private var ble: BLETapCoordinator<ContinuousClock>?
    #if os(iOS)
    private var hce: HCEPresentmentCoordinator?
    #endif

    init(keys: any CredentialKeyStore, records: any CredentialRecordStore, cards: any CardStore, statusTokens: any StatusTokenStore, counters: any CounterStore, foreground: ForegroundState, config: RemoteConfig, nfcEmulationEntitled: Bool, onCardsChanged: @escaping @MainActor () -> Void) {
        let scheduler = RenewalScheduler(renewer: CredentialRenewer(keys: keys, records: records, cards: cards, statusTokens: statusTokens), clock: ContinuousClock(),
                                         isForeground: { foreground.isActive }, onRenewed: onCardsChanged)
        self.scheduler = scheduler
        self.foreground = foreground
        self.config = config
        self.nfcEmulationEntitled = nfcEmulationEntitled
        makeProvider = { [selection] context in
            guard let (card, channel, _) = selection.current,
                  let credentialID = card.credentials[channel],
                  let record = try records.record(for: credentialID)
            else { throw ANError.keyUnavailable }
            return ANP1PhoneSession(
                material: try record.material(suspended: card.status == .suspended),
                signer: try keys.signer(for: credentialID, context: context),
                counters: counters
            )
        }
        // ADR-0023: perpanjangan memakai konteks autentikasi tap yang sama.
        prepare = { [selection] context in
            guard let (card, channel, tap) = selection.current else { return }
            await scheduler.beforePresentation(card: card, channel: channel, context: context, tap: tap)
        }
    }

    func start(card: Card, channel: ChannelKind) async -> AsyncStream<PresentmentEvent> {
        let tap = UUID()
        selection.current = (card, channel, tap)
        switch channel {
        case .ble:
            return observed(await bleCoordinator().tap(), tap: tap)
        case .nfcHCE:
            #if os(iOS)
            return observed(await hceCoordinator().present(), tap: tap)
            #else
            return Self.finished(.cancelled)
            #endif
        case .nfcSE, .wallet:
            return Self.finished(.cancelled)
        }
    }

    func cancel() async {
        scheduler.cancelPending()
        await ble?.cancel()
        #if os(iOS)
        await hce?.cancel()
        #endif
    }

    /// Meneruskan event tap, lalu menjalankan perpanjangan yang tertunda setelah aliran selesai.
    /// Perpanjangan berjalan di task terpisah agar tidak ikut dibatalkan saat aliran berakhir.
    private func observed(_ upstream: AsyncStream<PresentmentEvent>, tap: UUID) -> AsyncStream<PresentmentEvent> {
        let scheduler = scheduler
        return AsyncStream { continuation in
            let forwarding = Task {
                for await event in upstream { continuation.yield(event) }
                continuation.finish()
                Task { @MainActor in await scheduler.afterPresentation(tap: tap) }
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    /// Status radio Bluetooth bila central sudah dibuat.
    var bluetoothPoweredOn: Bool? {
        if central == nil, BLEAuthorization.current == .allowed {
            central = LiveBLECentral()  // izin sudah diberikan: tidak memicu prompt
        }
        return central?.isPoweredOn
    }

    /// `LiveBLECentral` memicu prompt izin Bluetooth, jadi dibuat saat pertama dipakai (FR-82).
    private func bleCoordinator() -> BLETapCoordinator<ContinuousClock> {
        if let ble { return ble }
        let foreground = foreground
        let central = central ?? LiveBLECentral()
        self.central = central
        let coordinator = BLETapCoordinator(
            central: central,
            authenticator: LAUserAuthenticator(),
            authenticationReason: localized("present.auth_reason"),
            makeProvider: makeProvider,
            prepare: prepare,
            isForeground: { foreground.isActive }
        )
        ble = coordinator
        return coordinator
    }

    #if os(iOS)
    private func hceCoordinator() -> HCEPresentmentCoordinator {
        if let hce { return hce }
        let coordinator = HCEPresentmentCoordinator(
            gate: NFCGate(capabilities: LiveNFCCapabilities(), entitled: nfcEmulationEntitled),
            config: config,
            authenticator: LAUserAuthenticator(),
            intents: LivePresentmentIntentProvider(),
            alertMessage: localized("present.hold_near_reader"),
            authenticationReason: localized("present.auth_reason"),
            makeSession: { try await LiveCardEmulationSession() },
            makeProvider: makeProvider,
            prepare: prepare
        )
        hce = coordinator
        return coordinator
    }
    #endif

    static func finished(_ event: PresentmentEvent) -> AsyncStream<PresentmentEvent> {
        AsyncStream { continuation in
            continuation.yield(event)
            continuation.finish()
        }
    }
}

/// Aliran event tetap untuk preview dan demo; tetap terbuka sampai dibatalkan.
@MainActor
final class ScriptedPresentationLauncher: PresentationLaunching {
    private let events: [PresentmentEvent]
    private let finishes: Bool
    private var continuation: AsyncStream<PresentmentEvent>.Continuation?

    init(events: [PresentmentEvent], finishes: Bool = false) {
        self.events = events
        self.finishes = finishes
    }

    func start(card: Card, channel: ChannelKind) async -> AsyncStream<PresentmentEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: PresentmentEvent.self)
        events.forEach { continuation.yield($0) }
        if finishes { continuation.finish() }
        self.continuation = continuation
        return stream
    }

    func cancel() async {
        continuation?.yield(.cancelled)
        continuation?.finish()
    }
}

#if DEBUG
extension AppServices {
    /// Data contoh untuk preview dan verifikasi visual (`-ANDemo`).
    /// `screen` adalah nilai `-ANDemoScreen`; nilai tak dikenal diabaikan. Layar Tambah Kartu memakai alamat
    /// layanan di TLD cadangan `.invalid` (RFC 2606) agar tampak tersedia tanpa pernah tersambung.
    public static func demo(screen raw: String? = nil) async -> AppServices {
        let screen = raw.flatMap(DemoScreen.init(rawValue:))
        let services = inMemory(events: screen?.presentmentEvents ?? [.waitingForReader],
                                apiBaseURL: screen?.opensAddCard == true ? URL(string: "https://demo.invalid") : nil)
        services.demoScreen = screen
        guard screen != .empty else { return services }
        let lobbyID = Data(repeating: 0x01, count: 16), meetingID = Data(repeating: 0x04, count: 16)
        _ = try? services.keys.createKey(for: lobbyID)
        _ = try? services.keys.createKey(for: meetingID)
        let samples = [
            Card(id: UUID(), name: "Lobi Utama", siteName: "Menara Anastrophe", zones: ["Lobi", "Lift A"], status: .active, credentials: [.ble: lobbyID], notAfter: .now.addingTimeInterval(6 * 86_400)),
            // Sisa < 24 jam: tampil "Perlu diperbarui" (FR-38, TC-DEV-10).
            Card(id: UUID(), name: "Ruang Rapat 7", siteName: "Menara Anastrophe", zones: ["Lantai 7"], status: .active, credentials: [.ble: meetingID], notAfter: .now.addingTimeInterval(12 * 3_600)),
            Card(id: UUID(), name: "Parkir B2", siteName: "Menara Anastrophe", zones: ["Parkir"], status: .active, credentials: [.ble: Data(repeating: 0x02, count: 16)], notAfter: nil),
            Card(id: UUID(), name: "Kantor Lt. 12", siteName: "Graha Mitra", zones: ["Lantai 12"], status: .suspended, credentials: [.ble: Data(repeating: 0x03, count: 16)], notAfter: nil),
        ]
        for card in samples { try? await services.cards.add(card) }
        // Riwayat contoh untuk kartu pertama (FR-30); lebih dari lima agar "Lihat semua" tampil (ADR-0030).
        for (index, hours) in [1, 9, 26, 50, 73, 97, 122, 170].enumerated() {
            let denied = index == 3
            try? await services.tapHistory.append(TapEntry(cardID: samples[0].id, date: .now.addingTimeInterval(Double(-hours * 3_600)), channel: .ble, granted: !denied, denyReason: denied ? .zoneNotAllowed : nil))
        }
        return services
    }
}
#endif

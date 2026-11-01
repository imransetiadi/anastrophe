import ANChannelBLE
import ANChannelNFC
import ANCore
import ANCrypto
import ANProtocol
import ANStorage
import ANWallet
import Foundation
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
    /// Store kartu tidak bisa dibuka; UI memberi tahu alih-alih menampilkan daftar kosong.
    public let storageFailed: Bool
    #if DEBUG
    /// Layar yang dibuka otomatis untuk verifikasi visual (`-ANDemoScreen`).
    public var demoScreen: String?
    #endif

    init(
        cards: any CardStore,
        keys: any CredentialKeyStore,
        records: any CredentialRecordStore,
        availability: @escaping @MainActor () async -> [ChannelKind: ChannelAvailability],
        launcher: any PresentationLaunching,
        foreground: ForegroundState,
        storageFailed: Bool = false
    ) {
        self.cards = cards
        self.keys = keys
        self.records = records
        self.availability = availability
        self.launcher = launcher
        self.foreground = foreground
        self.storageFailed = storageFailed
    }

    /// Dipakai bila `live()` gagal membuka penyimpanan: tidak ada presentasi, UI memberi tahu.
    public static func storageUnavailable() -> AppServices {
        let secrets = InMemorySecretStore()
        return AppServices(
            cards: EmptyCardStore(),
            keys: DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory()),
            records: KeychainCredentialRecordStore(store: secrets),
            availability: { [:] },
            launcher: ScriptedPresentationLauncher(events: [.cancelled], finishes: true),
            foreground: ForegroundState(),
            storageFailed: true
        )
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

    public static func live(nfcEmulationEntitled: Bool) throws -> AppServices {
        let secrets = deviceSecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: keyFactory())
        let records = KeychainCredentialRecordStore(store: secrets)
        let foreground = ForegroundState()
        let config = localConfig(nfcEmulationEntitled: nfcEmulationEntitled)
        let launcher = LivePresentationLauncher(keys: keys, records: records, counters: KeychainCounterStore(store: secrets), foreground: foreground, config: config, nfcEmulationEntitled: nfcEmulationEntitled)
        return AppServices(
            cards: try SwiftDataCardStore(directory: URL.applicationSupportDirectory.appending(path: "Anastrophe/Cards")),
            keys: keys,
            records: records,
            availability: { await liveAvailability(config: config, nfcEmulationEntitled: nfcEmulationEntitled, bluetoothPoweredOn: launcher.bluetoothPoweredOn) },
            launcher: launcher,
            foreground: foreground
        )
    }

    /// Penyimpanan sementara tanpa data (preview dan cadangan bila store gagal dibuka).
    public static func inMemory() -> AppServices {
        inMemory(events: [.waitingForReader])
    }

    static func inMemory(events: [PresentmentEvent]) -> AppServices {
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let directory = FileManager.default.temporaryDirectory.appending(path: "anastrophe-\(UUID().uuidString)")
        return AppServices(
            cards: (try? SwiftDataCardStore(directory: directory)) ?? EmptyCardStore(),
            keys: keys,
            records: KeychainCredentialRecordStore(store: secrets),
            availability: { [.ble: .available, .nfcHCE: .notEligible] },
            launcher: ScriptedPresentationLauncher(events: events),
            foreground: ForegroundState()
        )
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
}
#endif

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
    private var value: (card: Card, channel: ChannelKind)?

    var current: (card: Card, channel: ChannelKind)? {
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
    private let foreground: ForegroundState
    private let config: RemoteConfig
    private let nfcEmulationEntitled: Bool
    private var central: LiveBLECentral?
    private var ble: BLETapCoordinator<ContinuousClock>?
    #if os(iOS)
    private var hce: HCEPresentmentCoordinator?
    #endif

    init(keys: any CredentialKeyStore, records: any CredentialRecordStore, counters: any CounterStore, foreground: ForegroundState, config: RemoteConfig, nfcEmulationEntitled: Bool) {
        self.foreground = foreground
        self.config = config
        self.nfcEmulationEntitled = nfcEmulationEntitled
        makeProvider = { [selection] context in
            guard let (card, channel) = selection.current,
                  let credentialID = card.credentials[channel],
                  let record = try records.record(for: credentialID)
            else { throw ANError.keyUnavailable }
            return ANP1PhoneSession(
                material: try record.material(suspended: card.status == .suspended),
                signer: try keys.signer(for: credentialID, context: context),
                counters: counters
            )
        }
    }

    func start(card: Card, channel: ChannelKind) async -> AsyncStream<PresentmentEvent> {
        selection.current = (card, channel)
        switch channel {
        case .ble:
            return await bleCoordinator().tap()
        case .nfcHCE:
            #if os(iOS)
            return await hceCoordinator().present()
            #else
            return Self.finished(.cancelled)
            #endif
        case .nfcSE, .wallet:
            return Self.finished(.cancelled)
        }
    }

    func cancel() async {
        await ble?.cancel()
        #if os(iOS)
        await hce?.cancel()
        #endif
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
            makeProvider: makeProvider
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
    public static func demo(screen: String? = nil) async -> AppServices {
        let services = inMemory(events: screen == "bluetooth-denied" ? [.waitingForReader, .unavailable(.bluetoothUnauthorized)] : [.waitingForReader])
        services.demoScreen = screen
        let lobbyID = Data(repeating: 0x01, count: 16)
        _ = try? services.keys.createKey(for: lobbyID)
        let samples = [
            Card(id: UUID(), name: "Lobi Utama", siteName: "Menara Anastrophe", zones: ["Lobi", "Lift A"], status: .active, credentials: [.ble: lobbyID], notAfter: .now.addingTimeInterval(6 * 86_400)),
            Card(id: UUID(), name: "Parkir B2", siteName: "Menara Anastrophe", zones: ["Parkir"], status: .active, credentials: [.ble: Data(repeating: 0x02, count: 16)], notAfter: nil),
            Card(id: UUID(), name: "Kantor Lt. 12", siteName: "Graha Mitra", zones: ["Lantai 12"], status: .suspended, credentials: [.ble: Data(repeating: 0x03, count: 16)], notAfter: nil),
        ]
        for card in samples { try? await services.cards.add(card) }
        return services
    }
}
#endif

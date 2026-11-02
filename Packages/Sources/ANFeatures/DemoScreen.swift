#if DEBUG
import ANCore
import ANNetworking
import Foundation

/// Keadaan layar yang dibuka otomatis untuk verifikasi visual dan audit aksesibilitas (`-ANDemoScreen`,
/// ADR-0057). DEBUG saja; build Release tidak mengenal nilai ini.
public enum DemoScreen: String, CaseIterable, Sendable {
    case lab, help, detail, presentation, empty
    case bluetoothDenied = "bluetooth-denied"
    case detailSuspended = "detail-suspended"
    case presentationDenied = "presentation-denied"
    case add
    case addCode = "add-code"
    case addConfirm = "add-confirm"
    case addInvitation = "add-invitation"
    case addDone = "add-done"
    case addPending = "add-pending"
    case addFailed = "add-failed"

    /// Layar yang boleh dibuka otomatis dengan layanan live. Tanpa layar presentasi, karena itu akan memulai
    /// presentasi nyata tanpa pengguna memilih kartu (CLAUDE.md aturan 4), dan tanpa langkah Tambah Kartu buatan.
    public static func live(_ raw: String?) -> DemoScreen? {
        guard let screen = raw.flatMap(DemoScreen.init(rawValue:)), [.detail, .lab, .help].contains(screen) else { return nil }
        return screen
    }

    /// Layar yang membuka lembar Tambah Kartu pada langkah tertentu.
    var opensAddCard: Bool { rawValue.hasPrefix("add") }

    /// Naskah launcher demo: menunggu reader, lalu hasil sesuai layar.
    var presentmentEvents: [PresentmentEvent] {
        switch self {
        case .bluetoothDenied: [.waitingForReader, .unavailable(.bluetoothUnauthorized)]
        case .presentationDenied: [.waitingForReader, .denied(reason: .zoneNotAllowed)]
        default: [.waitingForReader]
        }
    }
}

/// Membawa lembar Tambah Kartu demo ke langkah layar, tanpa jaringan: galat field memakai validasi lokal,
/// dan langkah hasil diisi langsung.
enum AddCardDemo {
    static let siteName = "Menara Anastrophe"

    @MainActor
    static func apply(_ screen: DemoScreen, to model: AddCardModel) async {
        switch screen {
        case .addCode:
            model.chooseCard()
            model.codeInput = "AB-12"
            await model.submitCode()
        case .addConfirm:
            model.step = .confirmSite(SiteSummary(siteID: "demo", name: siteName))
        case .addInvitation:
            model.chooseInvitation()
            model.linkInput = "https://contoh.test/bukan-undangan"
            await model.submitInvitation()
        case .addDone:
            model.step = .done(Card(id: UUID(), name: "Lobi Utama", siteName: siteName, zones: ["Lobi", "Lift A"], status: .active,
                                    credentials: [:], notAfter: nil))
        case .addPending:
            model.step = .pending(siteName: siteName)
        case .addFailed:
            model.step = .failed(AddCardModel.failure(for: ANError.enrollmentRejected(.notRegistered)))
        default:
            break
        }
    }
}
#endif

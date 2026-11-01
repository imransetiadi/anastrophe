import ANFeatures
import SwiftUI

/// Memilih varian layanan app dan meneruskan perubahan `scenePhase`.
@MainActor
enum AppEnvironment {
    static func makeServices() async -> AppServices {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        let screen = arguments.firstIndex(of: "-ANDemoScreen").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        if arguments.contains("-ANDemo") {
            return await AppServices.demo(screen: screen)
        }
        #endif
        #if AN_NFC_EMULATION
        let nfcEmulationEntitled = true
        #else
        let nfcEmulationEntitled = false  // build tanpa entitlement HCE/SE (PRD D1)
        #endif
        // Alamat API enrolment dari Info.plist ANAPIBaseURL (AN_API_BASE_URL); DEBUG: -ANAPIBaseURL menimpanya.
        let apiBaseURL = BackendConfiguration.apiBaseURL(infoValue: Bundle.main.object(forInfoDictionaryKey: "ANAPIBaseURL") as? String, arguments: arguments)
        let services = (try? AppServices.live(nfcEmulationEntitled: nfcEmulationEntitled, apiBaseURL: apiBaseURL)) ?? AppServices.storageUnavailable(apiBaseURL: apiBaseURL)
        #if DEBUG
        // -ANLabBackend/-ANLabDevice/-ANLabSite, -ANLabRenew, -ANLabDelete, dan alur Tambah Kartu
        // (-ANLabCardReader, -ANLabOpenURL, -ANLabAddCode).
        services.configureLabBackend(arguments: arguments)
        // Verifikasi visual lab dengan layanan live; layar presentasi tidak dibuka otomatis karena
        // akan memulai presentasi nyata tanpa pengguna memilih kartu (CLAUDE.md aturan 4).
        services.demoScreen = ["detail", "lab", "help"].contains(screen ?? "") ? screen : nil
        #endif
        return services
    }

    static func handle(_ phase: ScenePhase, services: AppServices) {
        Task { await services.handleScenePhase(phase) }
    }
}

import ANFeatures
import SwiftUI

/// Memilih varian layanan app dan meneruskan perubahan `scenePhase`.
@MainActor
enum AppEnvironment {
    static func makeServices() async -> AppServices {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
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
        let services = (try? AppServices.live(nfcEmulationEntitled: nfcEmulationEntitled)) ?? AppServices.storageUnavailable()
        #if DEBUG
        services.configureLabBackend(arguments: arguments)  // -ANLabBackend <url> -ANLabDevice <id> -ANLabSite <id>, -ANLabRenew
        services.demoScreen = screen  // verifikasi visual alur lab dengan layanan live
        #endif
        return services
    }

    static func handle(_ phase: ScenePhase, services: AppServices) {
        Task { await services.handleScenePhase(phase) }
    }
}

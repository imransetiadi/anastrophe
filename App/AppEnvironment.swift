import ANFeatures
import SwiftUI

/// Memilih varian layanan app dan meneruskan perubahan `scenePhase`.
@MainActor
enum AppEnvironment {
    static func makeServices() async -> AppServices {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ANDemo") {
            let screen = arguments.firstIndex(of: "-ANDemoScreen").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            return await AppServices.demo(screen: screen)
        }
        #endif
        #if AN_NFC_EMULATION
        let nfcEmulationEntitled = true
        #else
        let nfcEmulationEntitled = false  // build tanpa entitlement HCE/SE (PRD D1)
        #endif
        return (try? AppServices.live(nfcEmulationEntitled: nfcEmulationEntitled)) ?? AppServices.storageUnavailable()
    }

    static func handle(_ phase: ScenePhase, services: AppServices) {
        Task { await services.handleScenePhase(phase) }
    }
}

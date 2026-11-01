import ANFeatures
import SwiftUI

@main
struct AnastropheApp: App {
    @State private var services: AppServices?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let services {
                    KeysView(services: services)
                } else {
                    ProgressView()
                }
            }
            .task { services = await AppEnvironment.makeServices() }
        }
        .onChange(of: scenePhase) { _, phase in
            if let services { AppEnvironment.handle(phase, services: services) }
        }
    }
}

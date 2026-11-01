import ANCore
import ANDesignSystem
import SwiftUI

/// Tab "Kunci": daftar kartu, detail, dan presentasi. Kartu ditampilkan sebagai
/// baris datar, bukan tumpukan pass bergaya Wallet (CLAUDE.md aturan 7).
public struct KeysView: View {
    private let services: AppServices
    @State private var model: KeysViewModel
    @State private var path: [Card.ID] = []
    @State private var presentation: PresentationController
    @State private var showsLab = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(services: AppServices) {
        self.services = services
        _model = State(initialValue: KeysViewModel(services: services))
        _presentation = State(initialValue: PresentationController(launcher: services.launcher))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            content
                .background(ANColor.background)
                .navigationTitle(localized("keys.title"))
                .navigationDestination(for: Card.ID.self) { id in
                    if let card = model.cards.first(where: { $0.id == id }) {
                        CardDetailView(card: card, presentability: model.presentability(of: card)) { use(card) }
                    }
                }
                .toolbar {
                    #if DEBUG
                    ToolbarItem(placement: .primaryAction) {
                        Button(localized("keys.lab")) { showsLab = true }
                    }
                    #endif
                }
        }
        .task {
            await model.load()
            openDemoScreen()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshAvailability() } }
        }
        .sheet(item: $presentation.request, onDismiss: {
            Task {
                await presentation.sheetDismissed()
                await model.refreshAvailability()  // mis. Bluetooth baru dinyalakan
            }
        }) { request in
            PresentationSheet(request: request, onCancel: cancel, onRetry: { use(request.card) })
                // Ukuran teks aksesibilitas langsung memakai detent besar agar panduan terbaca utuh.
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
        #if DEBUG
        .sheet(isPresented: $showsLab) {
            LabView(services: services) { Task { await model.load() } }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if services.storageFailed {
            ContentUnavailableView {
                Label(localized("storage.unavailable.title"), systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(localized("storage.unavailable.message"))
            }
        } else if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.cards.isEmpty {
            ContentUnavailableView {
                Label(localized("keys.empty.title"), systemImage: "key")
            } description: {
                Text(localized("keys.empty.message"))
            } actions: {
                #if DEBUG
                Button(localized("keys.add")) { showsLab = true }
                    .buttonStyle(ANPrimaryButtonStyle())
                    .disabled(!model.canAddCard)
                    .padding(.horizontal)
                #endif
            }
        } else {
            List(model.cards) { card in
                NavigationLink(value: card.id) {
                    CardRow(card: card, presentability: model.presentability(of: card)) { use(card) }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func use(_ card: Card) {
        guard case .available(let channel) = model.presentability(of: card) else { return }
        Task { await presentation.use(card, channel: channel) }
    }

    private func cancel() {
        Task { await presentation.cancel() }
    }

    private func openDemoScreen() {
        #if DEBUG
        switch services.demoScreen {
        case "lab": showsLab = true
        case "detail": if let first = model.cards.first { path = [first.id] }
        case "presentation", "bluetooth-denied": if let first = model.cards.first(where: { model.presentability(of: $0).canPresent }) { use(first) }
        default: break
        }
        #endif
    }
}

#if DEBUG
#Preview("Kunci") {
    @Previewable @State var services: AppServices?
    Group {
        if let services { KeysView(services: services) } else { ProgressView() }
    }
    .task { services = await AppServices.demo() }
}
#endif

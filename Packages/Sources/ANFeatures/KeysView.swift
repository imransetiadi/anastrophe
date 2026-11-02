import ANCore
import ANDesignSystem
import LocalAuthentication
import SwiftUI

/// Tab "Kunci": daftar kartu, detail, dan presentasi. Kartu ditampilkan sebagai
/// baris datar, bukan tumpukan pass bergaya Wallet (CLAUDE.md aturan 7).
public struct KeysView: View {
    private let services: AppServices
    @State private var model: KeysViewModel
    @State private var path: [Card.ID] = []
    @State private var presentation: PresentationController
    @State private var showsLab = false
    /// Layar Bantuan (ADR-0048).
    @State private var showsHelp = false
    @State private var deleteMessage: String?
    @State private var deleting: Card.ID?
    /// Alur Tambah Kartu (FR-10): dari tombol atau dari tautan undangan yang dibuka sistem.
    @State private var addCard: AddCardRequest?
    #if DEBUG
    @State private var labMessage: String?
    #endif
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
                #if DEBUG
                .safeAreaInset(edge: .bottom) { labBanner }
                #endif
                .navigationTitle(localized("keys.title"))
                .navigationDestination(for: Card.ID.self) { id in
                    if let card = model.cards.first(where: { $0.id == id }) {
                        CardDetailView(card: card, presentability: model.presentability(of: card), notice: model.renewalNotice(for: card), onDelete: { delete(card) }, isDeleting: deleting == card.id, history: model.history(for: card)) { use(card) }
                            #if DEBUG
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button(localized("lab.renew")) {
                                        Task {
                                            labMessage = await services.labRenew(card: card)
                                            await model.load()
                                        }
                                    }
                                    .accessibilityIdentifier("detail.lab_renew")
                                }
                            }
                            #endif
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { addCard = AddCardRequest(entry: .start) } label: {
                            Label(localized("keys.add"), systemImage: "plus")
                        }
                        .disabled(!model.canAddCard || services.storageFailed)
                        .accessibilityIdentifier("keys.add")
                    }
                    ToolbarItem(placement: Self.leadingPlacement) {
                        Button { showsHelp = true } label: {
                            Label(localized("keys.help"), systemImage: "questionmark.circle")
                        }
                        .accessibilityIdentifier("keys.help")
                    }
                    #if DEBUG
                    ToolbarItem(placement: Self.leadingPlacement) {
                        Button(localized("keys.lab")) { showsLab = true }
                            .accessibilityIdentifier("keys.lab")
                    }
                    #endif
                }
        }
        .task {
            await model.load()
            // FR-38 (ADR-0037): status dari server tanpa prompt; daftar dimuat ulang hanya bila berubah.
            if await services.refreshCardStatuses() { await model.load() }
            #if DEBUG
            // Daftar tampil dulu; alur lab berjalan sesudahnya agar host lambat tidak menahan layar.
            if let message = await services.runPendingLabBackendProvisioning() {
                labMessage = message
                await model.load()
            }
            if let message = await services.runPendingLabRenewal() {
                labMessage = message
                await model.load()
            }
            if let message = await services.runPendingLabDelete() {
                labMessage = message
                await model.load()
            }
            if let url = services.pendingLabOpenURL {
                services.pendingLabOpenURL = nil
                addCard = AddCardEntry.entry(for: url).map { AddCardRequest(entry: $0, labAutoSubmit: true) }
            } else if let code = services.pendingLabAddCode {
                services.pendingLabAddCode = nil
                addCard = AddCardRequest(entry: .start, labAutoCode: code)
            }
            #endif
            openDemoScreen()
        }
        .onOpenURL { url in
            // Tautan undangan https://<host>/i/<token> (FR-12). Tidak menyela presentasi yang sedang berjalan.
            guard let entry = AddCardEntry.entry(for: url), presentation.request == nil else { return }
            addCard = AddCardRequest(entry: entry)
        }
        .sheet(isPresented: $showsHelp) {
            HelpView(services: services)
        }
        .sheet(item: $addCard) { request in
            AddCardView(services: services, entry: request.entry, reader: services.makeCardReader(),
                        labAutoCode: request.labAutoCode, labAutoSubmit: request.labAutoSubmit) {
                Task { await model.load() }
            }
            #if DEBUG
            .demo(request.demoScreen)
            #endif
        }
        .alert(deleteMessage ?? "", isPresented: Binding(get: { deleteMessage != nil }, set: { if !$0 { deleteMessage = nil } })) {
            Button(localized("present.done"), role: .cancel) {}
        }
        .onChange(of: services.cardsRevision.value) { _, _ in
            Task { await model.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.load()
                    if await services.refreshCardStatuses() { await model.load() }
                }
            }
        }
        .sheet(item: $presentation.request, onDismiss: {
            Task {
                await presentation.sheetDismissed()
                await model.load()  // mis. Bluetooth baru dinyalakan, atau sertifikat baru diperpanjang
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
                Button(localized("keys.add")) { addCard = AddCardRequest(entry: .start) }
                    .buttonStyle(ANPrimaryButtonStyle())
                    .disabled(!model.canAddCard)
                    .padding(.horizontal)
                    .accessibilityIdentifier("keys.empty.add")
            }
        } else {
            List(model.cards) { card in
                NavigationLink(value: card.id) {
                    CardRow(card: card, presentability: model.presentability(of: card)) { use(card) }
                }
                // Permukaan baris memakai token `card` (design system §3), juga di mode gelap.
                .listRowBackground(ANColor.card)
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("keys.list")
        }
    }

    private static var leadingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }

    #if DEBUG
    /// Hasil provisioning dari argumen `-ANLabBackend` (DEBUG saja).
    @ViewBuilder
    private var labBanner: some View {
        if let labMessage {
            Text(labMessage)
                .font(.footnote)
                .foregroundStyle(ANColor.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
        }
    }
    #endif

    private func delete(_ card: Card) {
        guard deleting == nil else { return }
        deleting = card.id
        Task {
            defer { deleting = nil }
            do {
                try await services.removeCard(card)
                path.removeAll()
                await model.load()
            } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
                // Dibatalkan pengguna: tanpa pesan.
            } catch is URLError {
                deleteMessage = localized("detail.delete.failed")
            } catch {
                deleteMessage = localized("detail.delete.failed_generic")
            }
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
        guard let screen = services.demoScreen else { return }
        switch screen {
        case .lab: showsLab = true
        case .help: showsHelp = true
        case .detail: if let first = model.cards.first { path = [first.id] }
        case .detailSuspended: if let card = model.cards.first(where: { $0.status == .suspended }) { path = [card.id] }
        case .presentation, .bluetoothDenied, .presentationDenied:
            if let first = model.cards.first(where: { model.presentability(of: $0).canPresent }) { use(first) }
        case .empty: break
        case .add, .addCode, .addConfirm, .addInvitation, .addDone, .addPending, .addFailed:
            addCard = AddCardRequest(entry: .start, demoScreen: screen)
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

import ANCore
import ANDesignSystem
import ANNetworking
import ANNFCEnroll
import SwiftUI

/// Permintaan menampilkan lembar Tambah Kartu. Data otomasi lab (DEBUG) ikut di dalam item: konten
/// `sheet(item:)` dibangun dari item yang dipresentasikan, bukan dari `@State` lain yang bisa masih bernilai
/// lama saat sheet pertama kali dibuka.
struct AddCardRequest: Identifiable {
    let id = UUID()
    let entry: AddCardEntry
    var labAutoCode: String?
    var labAutoSubmit = false
    #if DEBUG
    /// Langkah demo untuk audit aksesibilitas (`-ANDemoScreen add-*`, ADR-0057).
    var demoScreen: DemoScreen?
    #endif
}

/// Lembar Tambah Kartu Akses (FR-10–FR-13, ADR-0043). Mengikuti `pages/ios-app.md`:
/// - satu tindakan utama per layar;
/// - label terlihat di atas field, galat di dekat field;
/// - tombol nonaktif dengan indikator selama permintaan berjalan;
/// - teks tanpa istilah teknis.
struct AddCardView: View {
    @State private var model: AddCardModel
    private let entry: AddCardEntry
    private let labAutoCode: String?
    private let labAutoSubmit: Bool
    private let onFinished: () -> Void
    #if DEBUG
    private var demoScreen: DemoScreen?
    #endif
    @Environment(\.dismiss) private var dismiss

    /// `labAutoCode` dan `labAutoSubmit` hanya dipakai DEBUG untuk e2e di simulator (`-ANLabAddCode`,
    /// `-ANLabOpenURL`).
    init(services: AppServices, entry: AddCardEntry, reader: any CardOwnershipReader, labAutoCode: String? = nil, labAutoSubmit: Bool = false,
         onFinished: @escaping () -> Void) {
        _model = State(initialValue: AddCardModel(services: services, reader: reader))
        self.entry = entry
        self.labAutoCode = labAutoCode
        self.labAutoSubmit = labAutoSubmit
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("add.scroll")
            .background(ANColor.background)
            .navigationTitle(localized("add.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if showsBack {
                        Button(localized("add.back")) { model.back() }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("add.back")
                    } else {
                        Button(localized("add.close")) { dismiss() }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("add.close")
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .sensoryFeedback(trigger: model.step) { _, step in
            switch step {
            case .done: .success
            case .failed: .error
            default: nil
            }
        }
        .task { await start() }
    }

    #if DEBUG
    /// Membuka lembar pada langkah demo (`-ANDemoScreen add-*`) tanpa jaringan.
    func demo(_ screen: DemoScreen?) -> AddCardView {
        var copy = self
        copy.demoScreen = screen
        return copy
    }
    #endif

    private var showsBack: Bool {
        switch model.step {
        case .siteCode, .confirmSite, .invitation: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .chooseMethod: chooseMethod
        case .siteCode: siteCode
        case .confirmSite(let site): confirm(site)
        case .invitation: invitation
        case .working: working
        case .done(let card): done(card)
        case .pending(let siteName): pending(siteName)
        case .failed(let failure): failed(failure)
        }
    }

    // MARK: Langkah

    @ViewBuilder
    private var chooseMethod: some View {
        Text(localized("add.intro"))
            .foregroundStyle(ANColor.mutedForeground)
        if !model.isServiceAvailable {
            Label(localized("add.error.service_unavailable"), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(ANColor.warning)
        }
        methodButton(localized("add.method.card"), detail: localized("add.method.card.detail"), systemImage: "creditcard") { model.chooseCard() }
            .accessibilityIdentifier("add.method.card")
        methodButton(localized("add.method.invitation"), detail: localized("add.method.invitation.detail"), systemImage: "link") { model.chooseInvitation() }
            .accessibilityIdentifier("add.method.invitation")
    }

    @ViewBuilder
    private var siteCode: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("add.code.label"))
                .font(.headline)
            // Field ≥ 44 pt (design system §4): monospace, kapital semua, keyboard ASCII, Return "Lanjut".
            ANTextField(localized("add.code.label"), text: $model.codeInput, prompt: "XXXX-XXXX", kind: .code,
                        identifier: "add.code.field") {
                Task { await model.submitCode() }
            }
            Text(localized("add.code.help"))
                .font(.footnote)
                .foregroundStyle(ANColor.mutedForeground)
            fieldError
        }
        primaryButton(localized("add.continue")) { await model.submitCode() }
    }

    @ViewBuilder
    private func confirm(_ site: SiteSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "building.2")
                .foregroundStyle(ANColor.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("add.confirm.caption"))
                    .font(.footnote)
                    .foregroundStyle(ANColor.mutedForeground)
                Text(site.name)
                    .font(.title3.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        Text(localized("add.confirm.message"))
        primaryButton(localized("add.confirm.read")) { await model.confirmAndRead() }
            .accessibilityIdentifier("add.confirm.read")
        secondaryButton(localized("add.confirm.wrong_site")) { model.back() }
    }

    @ViewBuilder
    private var invitation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("add.link.label"))
                .font(.headline)
            // Field ≥ 44 pt (design system §4): tanpa kapital, keyboard URL, Return "Buka".
            ANTextField(localized("add.link.label"), text: $model.linkInput, prompt: "https://…/i/…", kind: .url,
                        identifier: "add.link.field") {
                Task { await model.submitInvitation() }
            }
            Text(localized("add.link.help"))
                .font(.footnote)
                .foregroundStyle(ANColor.mutedForeground)
            fieldError
        }
        primaryButton(localized("add.link.submit")) { await model.submitInvitation() }
    }

    private var working: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(localized("add.working"))
                .foregroundStyle(ANColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func done(_ card: Card) -> some View {
        resultHeader(localized("add.done.title"), systemImage: "checkmark.circle.fill", tint: ANColor.success)
            .accessibilityIdentifier("add.result.done")
        VStack(alignment: .leading, spacing: 4) {
            Text(card.siteName)
                .font(.headline)
            if !card.zones.isEmpty {
                Text(card.zones.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(ANColor.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
        Button(localized("add.finish")) {
            onFinished()
            dismiss()
        }
        .buttonStyle(ANPrimaryButtonStyle())
    }

    @ViewBuilder
    private func pending(_ siteName: String?) -> some View {
        resultHeader(localized("add.pending.title"), systemImage: "clock", tint: ANColor.warning)
            .accessibilityIdentifier("add.result.pending")
        if let siteName {
            Text(siteName)
                .font(.headline)
        }
        Text(localized("add.pending.message"))
        Button(localized("add.finish")) { dismiss() }
            .buttonStyle(ANPrimaryButtonStyle())
    }

    @ViewBuilder
    private func failed(_ failure: AddCardModel.Failure) -> some View {
        resultHeader(localized("add.failed.title"), systemImage: "exclamationmark.triangle", tint: ANColor.destructive)
            .accessibilityIdentifier("add.result.failed")
        Text(failure.message)
        if failure.offersInvitation {
            // FR-13: kartu tak terdaftar atau tak terbaca → jalur undangan sebagai tindakan utama.
            Button(localized("add.method.invitation")) { model.chooseInvitation() }
                .buttonStyle(ANPrimaryButtonStyle())
            secondaryButton(localized("add.retry")) { model.back() }
        } else {
            Button(localized("add.retry")) { model.back() }
                .buttonStyle(ANPrimaryButtonStyle())
        }
    }

    // MARK: Komponen

    @ViewBuilder
    private var fieldError: some View {
        if let error = model.fieldError {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(ANColor.destructive)
                .accessibilityIdentifier("add.field_error")
        }
    }

    private func resultHeader(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .font(.title2.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityAddTraits(.isHeader)
        .onAppear { AccessibilityNotification.Announcement(title).post() }
    }

    /// Tombol aksi utama async: nonaktif dan menampilkan indikator selama permintaan berjalan.
    private func primaryButton(_ title: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if model.isBusy {
                    ProgressView()
                        .tint(ANColor.onAccent)
                }
                Text(title)
            }
        }
        .buttonStyle(ANPrimaryButtonStyle())
        .disabled(model.isBusy)
    }

    /// Tombol teks sekunder; area ketuk 44 pt ada di dalam gaya, bukan bingkai di luar tombol.
    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ANSecondaryButtonStyle())
            .disabled(model.isBusy)
    }

    /// Pilihan cara menambah kartu: baris datar dengan ikon, judul, dan keterangan (bukan gaya pass Wallet).
    private func methodButton(_ title: String, detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(ANColor.primary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ANColor.foreground)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(ANColor.mutedForeground)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ANColor.mutedForeground)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(ANColor.card, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!model.isServiceAvailable)
        .accessibilityElement(children: .combine)
    }

    // MARK: Masuk

    private func start() async {
        #if DEBUG
        if let demoScreen {
            await AddCardDemo.apply(demoScreen, to: model)
            return
        }
        #endif
        switch entry {
        case .invitation(let url):
            model.prefill(invitationURL: url)
            #if DEBUG
            if labAutoSubmit { await model.submitInvitation() }
            #endif
        case .start:
            #if DEBUG
            if let labAutoCode {
                model.chooseCard()
                model.codeInput = labAutoCode
                await model.submitCode()
                await model.confirmAndRead()
            }
            #endif
        }
    }
}

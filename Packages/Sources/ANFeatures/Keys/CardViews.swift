import ANCore
import ANDesignSystem
import SwiftUI

/// Badge status: ikon + teks, tidak hanya warna (design system §3).
struct StatusBadge: View {
    let status: CardStatus

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .active: localized("card.status.active")
        case .pendingApproval: localized("card.status.pending_approval")
        case .suspended: localized("card.status.suspended")
        case .needsRenewal: localized("card.status.needs_renewal")
        case .revoked: localized("card.status.revoked")
        case .needsTransfer: localized("card.status.needs_transfer")
        }
    }

    private var symbol: String {
        switch status {
        case .active: "checkmark.circle.fill"
        case .pendingApproval: "hourglass"
        case .suspended: "pause.circle.fill"
        case .needsRenewal: "exclamationmark.triangle.fill"
        case .revoked: "xmark.octagon.fill"
        case .needsTransfer: "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch status {
        case .active: ANColor.success
        case .pendingApproval: ANColor.mutedForeground
        case .suspended, .needsRenewal, .needsTransfer: ANColor.warning
        case .revoked: ANColor.destructive
        }
    }
}

/// Baris kartu datar (bukan tumpukan pass bergaya Wallet, CLAUDE.md aturan 7).
struct CardRow: View {
    let card: Card
    let presentability: Presentability
    let onUse: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Image(systemName: "building.2")
                .font(.title2)
                .foregroundStyle(ANColor.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name).font(.headline).foregroundStyle(ANColor.foreground)
                Text(card.siteName).font(.subheadline).foregroundStyle(ANColor.mutedForeground)
                StatusBadge(status: card.displayStatus())
            }
            Spacer(minLength: 8)
            if presentability.canPresent {
                Button(localized("keys.use"), action: onUse)
                    .buttonStyle(.borderedProminent)
                    .tint(ANColor.accent)
                    .foregroundStyle(ANColor.onAccent)
                    .frame(minHeight: 44)
                    .accessibilityHint(card.name)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Detail kartu (FR-30, subset R1). Satu aksi utama: "Gunakan kartu".
struct CardDetailView: View {
    let card: Card
    let presentability: Presentability
    var notice: RenewalNotice?
    var onDelete: (() -> Void)?
    var isDeleting = false
    var history: [TapEntry] = []
    let onUse: () -> Void
    @State private var confirmsDelete = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section {
                LabeledContent(localized("detail.site"), value: card.siteName)
                LabeledContent(localized("detail.zones"), value: card.zones.joined(separator: ", "))
                // Di ukuran aksesibilitas label dan badge ditumpuk, seperti baris lain, agar teks badge tidak terpotong.
                let statusLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                statusLayout {
                    Text(localized("detail.status"))
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    StatusBadge(status: card.displayStatus())
                }
                // Tanpa ini separator mengikuti teks badge, bukan tepi baris seperti baris lain.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                LabeledContent(localized("detail.channels"), value: channels)
                if let notAfter = card.notAfter {
                    LabeledContent(localized("detail.expires"), value: notAfter.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                Button(localized("detail.use"), action: onUse)
                    .buttonStyle(ANPrimaryButtonStyle())
                    .disabled(!presentability.canPresent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let notice {
                    // TC-DEV-10: perpanjangan butuh internet saat kartu dipakai berikutnya.
                    Text(notice == .needsInternet ? localized("card.renewal_offline") : localized("card.renewal_hint"))
                        .font(.footnote)
                        .foregroundStyle(ANColor.mutedForeground)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if case .unavailable(let reason) = presentability {
                    Text(Self.text(for: reason))
                        .font(.footnote)
                        .foregroundStyle(ANColor.mutedForeground)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            // FR-30: riwayat tap lokal 30 hari, hanya di perangkat; lima terbaru di sini (ADR-0030).
            Section(localized("detail.history")) {
                let preview = TapHistoryPreview(history)
                if preview.inline.isEmpty {
                    Text(localized("detail.history.empty"))
                        .font(.footnote)
                        .foregroundStyle(ANColor.mutedForeground)
                } else {
                    ForEach(preview.inline) { entry in
                        TapHistoryRow(entry: entry)
                    }
                    if preview.showsAll {
                        NavigationLink {
                            TapHistoryList(entries: history)
                        } label: {
                            LabeledContent(localized("detail.history.see_all"), value: preview.total.formatted())
                        }
                    }
                }
            }
            if onDelete != nil {
                // FR-31: Detail → Pengaturan → Hapus, dengan konfirmasi + autentikasi.
                Section(localized("detail.settings")) {
                    Button(role: .destructive) { confirmsDelete = true } label: {
                        HStack {
                            Text(localized("detail.delete"))
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeleting)  // aksi async: cegah ketukan ganda
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ANColor.background)
        .navigationTitle(card.name)
        .confirmationDialog(localized("detail.delete.confirm_title"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(localized("detail.delete"), role: .destructive) { onDelete?() }
        } message: {
            Text(localized("detail.delete.confirm_message"))
        }
    }

    private var channels: String {
        card.credentials.keys.sorted { $0.rawValue < $1.rawValue }.map { channel in
            switch channel {
            case .ble: localized("channel.ble")
            case .nfcHCE, .nfcSE: localized("channel.tap")
            case .wallet: localized("channel.wallet")
            }
        }.joined(separator: ", ")
    }

    static func text(for reason: Presentability.Reason) -> String {
        switch reason {
        case .needsTransfer: localized("card.reason.needs_transfer")
        case .suspended: localized("card.reason.suspended")
        case .revoked: localized("card.reason.revoked")
        case .pendingApproval: localized("card.reason.pending_approval")
        case .expired: localized("card.reason.expired")
        case .bluetoothOff: localized("card.reason.bluetooth_off")
        case .bluetoothUnauthorized: localized("card.reason.bluetooth_denied")
        case .noChannel: localized("card.reason.no_channel")
        }
    }
}

/// Ringkasan riwayat di detail (ADR-0030): lima tap terbaru; sisanya lewat "Lihat semua".
struct TapHistoryPreview: Equatable {
    static let inlineLimit = 5
    let inline: [TapEntry]
    let total: Int
    var showsAll: Bool { total > inline.count }

    init(_ entries: [TapEntry]) {
        inline = Array(entries.prefix(Self.inlineLimit))
        total = entries.count
    }
}

/// Riwayat tap 30 hari lengkap (FR-30, ADR-0030), terbaru di atas.
struct TapHistoryList: View {
    let entries: [TapEntry]

    var body: some View {
        List(entries) { entry in
            TapHistoryRow(entry: entry)
        }
        .scrollContentBackground(.hidden)
        .background(ANColor.background)
        .navigationTitle(localized("detail.history"))
    }
}

/// Satu baris riwayat: hasil (ikon + teks, tidak hanya warna) dan waktu.
struct TapHistoryRow: View {
    let entry: TapEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.granted ? ANColor.success : ANColor.destructive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(ANColor.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard !entry.granted else { return localized("detail.history.granted") }
        let reason: String = switch entry.denyReason ?? .unknown {
        case .expired: localized("history.reason.expired")
        case .suspended: localized("history.reason.suspended")
        case .revoked: localized("history.reason.revoked")
        case .outsideSchedule: localized("history.reason.outside_schedule")
        case .zoneNotAllowed: localized("history.reason.zone_not_allowed")
        case .unknown: localized("history.reason.unknown")
        }
        return "\(localized("detail.history.denied")) · \(reason)"
    }
}

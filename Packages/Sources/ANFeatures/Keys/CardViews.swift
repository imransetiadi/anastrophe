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
                StatusBadge(status: card.status)
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
    let onUse: () -> Void

    var body: some View {
        List {
            Section {
                LabeledContent(localized("detail.site"), value: card.siteName)
                LabeledContent(localized("detail.zones"), value: card.zones.joined(separator: ", "))
                HStack {
                    Text(localized("detail.status"))
                    Spacer(minLength: 8)
                    StatusBadge(status: card.status)
                }
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
                if case .unavailable(let reason) = presentability {
                    Text(Self.text(for: reason))
                        .font(.footnote)
                        .foregroundStyle(ANColor.mutedForeground)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ANColor.background)
        .navigationTitle(card.name)
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

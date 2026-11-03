import ANCore
import ANDesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Lembar presentasi kanal N dan B (design system §5). Teks tanpa istilah teknis (FR-26).
struct PresentationSheet: View {
    let request: PresentationRequest
    let onCancel: () -> Void
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Mulai saat sesi benar-benar menunggu reader (setelah cooldown), bukan saat lembar muncul.
    @State private var countdownStart: Date?
    @State private var cooldownUntil: Date?

    private var model: PresentationViewModel { request.model }

    var body: some View {
        // ScrollView + aksi tersemat: teks panduan tidak pernah terpotong, juga di AX5 (NFR-A01).
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ANColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("present.title")
                if let detail {
                    Text(detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ANColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("present.detail")
                }
                if model.phase == .unavailable(.bluetoothUnauthorized), let settings = Self.settingsURL {
                    // `Link` memakai `ButtonStyle`, jadi bingkai gaya menjadi area ketuk tautan itu sendiri. Ukuran besar:
                    // lihat `actions` di bawah.
                    Link(localized("present.open_settings"), destination: settings)
                        .buttonStyle(ANSecondaryButtonStyle())
                        .controlSize(.large)
                        .accessibilityIdentifier("present.open_settings")
                }
                if case .coolingDown = model.phase, let cooldownUntil {
                    ProgressView(timerInterval: Date.now...max(Date.now, cooldownUntil), countsDown: true) {
                        Text(localized("present.time_left"))
                    }
                    .tint(ANColor.warning)
                } else if request.channel == .nfcHCE, !model.isFinished, let countdownStart {
                    ProgressView(timerInterval: countdownStart...countdownStart.addingTimeInterval(60), countsDown: true) {
                        Text(localized("present.time_left"))
                    }
                    .tint(ANColor.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .accessibilityIdentifier("present.scroll")
        .safeAreaInset(edge: .bottom) {
            actions
                // Lembar setengah tinggi tampil diperkecil sistem (±96 %): ukuran besar (50 pt) menjaga area ketuk tombol
                // tetap ≥ 44 pt di layar (design system §4).
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(ANColor.background)
        }
        .background(ANColor.background)
        .task(id: request.id) { await model.start() }
        .sensoryFeedback(trigger: model.phase) { _, phase in
            switch phase {
            case .granted: .success
            case .denied: .error
            default: nil
            }
        }
        .onChange(of: model.phase, initial: true) { _, phase in
            switch phase {
            case .coolingDown(let seconds):
                cooldownUntil = .now.addingTimeInterval(TimeInterval(seconds))
            case .waiting where countdownStart == nil:
                countdownStart = .now
            default:
                break
            }
            AccessibilityNotification.Announcement(title).post()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isFinished {
            VStack(spacing: 8) {
                Button(localized("present.done")) { dismiss() }
                    .buttonStyle(ANPrimaryButtonStyle())
                    .accessibilityIdentifier("present.done")
                if model.phase != .granted {
                    Button(localized("present.retry"), action: onRetry)
                        .buttonStyle(ANSecondaryButtonStyle())
                        .accessibilityIdentifier("present.retry")
                }
            }
        } else {
            Button(localized("present.cancel"), role: .cancel, action: onCancel)
                .buttonStyle(ANSecondaryButtonStyle())
                .accessibilityIdentifier("present.cancel")
        }
    }

    private var title: String {
        switch model.phase {
        case .waiting: request.channel == .ble ? localized("present.searching") : localized("present.hold_near_reader")
        case .coolingDown: localized("present.cooling_down")
        case .readerFound: localized("present.reader_found")
        case .exchanging: localized("present.exchanging")
        case .granted: localized("present.granted")
        case .denied: localized("present.denied")
        case .timedOut: localized("present.timed_out")
        case .cancelled: localized("present.cancelled")
        case .unavailable(.bluetoothOff): localized("present.bluetooth_off")
        case .unavailable(.bluetoothUnauthorized): localized("present.bluetooth_denied")
        case .unavailable: localized("present.unavailable")
        case .readerOutOfRange: localized("present.reader_out_of_range")
        }
    }

    private var detail: String? {
        if case .unavailable(let availability) = model.phase {
            return switch availability {
            case .bluetoothOff: localized("present.bluetooth_off.detail")
            case .bluetoothUnauthorized: localized("present.bluetooth_denied.detail")
            default: nil
            }
        }
        if model.phase == .readerOutOfRange { return localized("present.reader_out_of_range.detail") }
        guard case .denied(let reason) = model.phase else { return nil }
        return switch reason {
        case .expired: localized("present.denied.expired")
        case .suspended: localized("present.denied.suspended")
        case .revoked: localized("present.denied.revoked")
        case .outsideSchedule: localized("present.denied.schedule")
        case .zoneNotAllowed: localized("present.denied.zone")
        case .unknown: localized("present.denied.unknown")
        }
    }

    private var symbol: String {
        switch model.phase {
        case .waiting, .readerFound, .exchanging: request.channel == .ble ? "dot.radiowaves.left.and.right" : "iphone.radiowaves.left.and.right"
        case .coolingDown: "hourglass"
        case .granted: "lock.open.fill"
        case .denied: "xmark.octagon.fill"
        case .timedOut: "clock.badge.exclamationmark"
        case .cancelled: "xmark.circle"
        case .unavailable: "antenna.radiowaves.left.and.right.slash"
        case .readerOutOfRange: "wave.3.right"
        }
    }

    private static var settingsURL: URL? {
        #if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }

    private var tint: Color {
        switch model.phase {
        case .granted: ANColor.success
        case .denied: ANColor.destructive
        case .timedOut, .coolingDown, .unavailable, .readerOutOfRange: ANColor.warning
        default: ANColor.primary
        }
    }
}

/// Satu presentasi yang sedang berjalan.
struct PresentationRequest: Identifiable {
    let id = UUID()
    let card: Card
    let channel: ChannelKind
    let model: PresentationViewModel
}

import ANCore
import ANDesignSystem
import SwiftUI

/// Layar Bantuan dari tab Kunci (ADR-0048): cara akses di iPhone ini, FAQ sepuluh topik (FR-60),
/// iPhone yang didukung (FR-02), dan laporan diagnostik tanpa rahasia (FR-63). Tanpa jaringan.
struct HelpView: View {
    let services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var availability: [ChannelKind: ChannelAvailability] = [:]
    @State private var report: String?

    var body: some View {
        NavigationStack {
            List {
                Section(localized("help.section.channels")) {
                    channelRow(localized("channel.tap"), systemImage: "iphone.radiowaves.left.and.right", availability: availability[.nfcHCE])
                    channelRow(localized("channel.ble"), systemImage: "antenna.radiowaves.left.and.right", availability: availability[.ble])
                }
                Section(localized("help.section.faq")) {
                    ForEach(HelpTopic.allCases) { topic in
                        DisclosureGroup {
                            Text(topic.answer)
                                .padding(.vertical, 4)
                        } label: {
                            Text(topic.question)
                                .font(.headline)
                        }
                    }
                }
                Section {
                    Label(localized("help.devices.list"), systemImage: "iphone")
                } header: {
                    Text(localized("help.section.devices"))
                } footer: {
                    Text(localized("help.devices.note"))
                }
                Section {
                    if let report {
                        ShareLink(item: report) {
                            Label(localized("help.diagnostics.share"), systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                } header: {
                    Text(localized("help.section.diagnostics"))
                } footer: {
                    Text(localized("help.diagnostics.note"))
                }
                Section(localized("help.section.support")) {
                    Label(localized("help.support.text"), systemImage: "building.2")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ANColor.background)
            .navigationTitle(localized("help.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("present.done")) { dismiss() }
                }
            }
            .task {
                availability = await services.availability()
                report = DiagnosticsReport.text(await services.diagnosticsInput())
            }
        }
    }

    /// Satu cara akses dan statusnya di iPhone ini; VoiceOver membacanya sebagai satu elemen.
    private func channelRow(_ name: String, systemImage: String, availability: ChannelAvailability?) -> some View {
        LabeledContent {
            Text(HelpContent.status(for: availability))
                .foregroundStyle(ANColor.mutedForeground)
        } label: {
            Label(name, systemImage: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

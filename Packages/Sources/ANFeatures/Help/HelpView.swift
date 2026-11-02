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
            // Semua baris memakai permukaan token `card` (design system §3), juga di mode gelap; judul dan catatan seksi
            // memakai token `mutedForeground` (ADR-0058).
            List {
                Section {
                    channelRow(localized("channel.tap"), systemImage: "iphone.radiowaves.left.and.right", availability: availability[.nfcHCE])
                    channelRow(localized("channel.ble"), systemImage: "antenna.radiowaves.left.and.right", availability: availability[.ble])
                } header: {
                    ANMutedText(localized("help.section.channels"))
                }
                Section {
                    ForEach(HelpTopic.allCases) { topic in
                        DisclosureGroup {
                            Text(topic.answer)
                                .padding(.vertical, 4)
                                .listRowBackground(ANColor.card)
                        } label: {
                            Text(topic.question)
                                .font(.headline)
                        }
                        .accessibilityIdentifier("help.faq.\(topic.rawValue)")
                        .listRowBackground(ANColor.card)
                    }
                } header: {
                    ANMutedText(localized("help.section.faq"))
                }
                Section {
                    Label(localized("help.devices.list"), systemImage: "iphone")
                        .listRowBackground(ANColor.card)
                } header: {
                    ANMutedText(localized("help.section.devices"))
                } footer: {
                    ANMutedText(localized("help.devices.note"))
                }
                Section {
                    if let report {
                        ShareLink(item: report) {
                            Label(localized("help.diagnostics.share"), systemImage: "square.and.arrow.up")
                        }
                        .listRowBackground(ANColor.card)
                    } else {
                        ProgressView()
                            .listRowBackground(ANColor.card)
                    }
                } header: {
                    ANMutedText(localized("help.section.diagnostics"))
                } footer: {
                    ANMutedText(localized("help.diagnostics.note"))
                }
                Section {
                    Label(localized("help.support.text"), systemImage: "building.2")
                        .listRowBackground(ANColor.card)
                } header: {
                    ANMutedText(localized("help.section.support"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ANColor.background)
            .accessibilityIdentifier("help.list")
            .navigationTitle(localized("help.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("present.done")) { dismiss() }
                        .accessibilityIdentifier("help.done")
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
        .listRowBackground(ANColor.card)
    }
}

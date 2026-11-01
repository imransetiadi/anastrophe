#if DEBUG
import ANCore
import ANDesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Layar lab (DEBUG saja): ambil kartu dari backend dev, atau buat kunci, jalankan
/// `lab_ca.py issue`, lalu tempel JSON hasilnya.
struct LabView: View {
    let services: AppServices
    let onCardsChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var channel: ChannelKind = .ble
    @State private var begun: (credentialID: Data, publicKey: Data)?
    @State private var json = ""
    @State private var message: String?
    @State private var busy = false
    @State private var backendURL = "http://127.0.0.1:8080"
    @State private var deviceID = ""
    @State private var siteID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(localized("lab.channel"), selection: $channel) {
                        Text(localized("channel.ble")).tag(ChannelKind.ble)
                        Text(localized("channel.tap")).tag(ChannelKind.nfcHCE)
                    }
                }
                Section(localized("lab.backend")) {
                    labeledField(localized("lab.backend.url"), text: $backendURL, prompt: "http://127.0.0.1:8080", isURL: true)
                    labeledField(localized("lab.backend.device"), text: $deviceID, prompt: "UUID", isURL: false)
                    labeledField(localized("lab.backend.site"), text: $siteID, prompt: "UUID", isURL: false)
                    Button { Task { await provisionFromBackend() } } label: {
                        HStack {
                            Text(localized("lab.backend.provision"))
                            if busy {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(backendTarget == nil || busy)
                }
                Section(localized("lab.step1")) {
                    Button(localized("lab.create_key"), action: begin).disabled(busy)
                    if let command {
                        Text(command)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button(localized("lab.copy")) { copy(command) }
                    }
                }
                Section(localized("lab.step2")) {
                    TextEditor(text: $json)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 160)
                        .autocorrectionDisabled()
                    Button(localized("lab.import")) { Task { await importCard() } }
                        .disabled(json.isEmpty || begun == nil || busy)
                }
                if let message {
                    Section { Text(message) }
                }
            }
            .navigationTitle(localized("lab.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("present.done")) { dismiss() }
                }
            }
        }
    }

    private var command: String? {
        guard let begun else { return nil }
        return "python3 scripts/anp1/lab_ca.py issue --cred-id \(begun.credentialID.hexString) --pubkey \(begun.publicKey.hexString) --channel \(channel.rawValue)"
    }

    private func begin() {
        message = nil
        do {
            begun = try LabProvisioning.begin(keys: services.keys)
        } catch {
            message = localized("lab.failed")
        }
    }

    private func importCard() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await LabProvisioning.complete(json: Data(json.utf8), keys: services.keys, records: services.records, cards: services.cards)
            message = localized("lab.imported")
            json = ""
            begun = nil
            onCardsChanged()
        } catch ANError.cardLimitReached {
            message = localized("lab.limit")
        } catch {
            message = localized("lab.failed")
        }
    }

    private var backendTarget: LabBackendTarget? {
        LabBackendTarget(url: backendURL, deviceID: deviceID, siteID: siteID)
    }

    private func provisionFromBackend() async {
        guard let backendTarget else { return }
        busy = true
        defer { busy = false }
        message = await services.provisionFromLabBackend(backendTarget, channel: channel)
        onCardsChanged()
    }

    /// Label terlihat di atas field (bukan placeholder saja); ID ditempel dari keluaran devseed.
    private func labeledField(_ label: String, text: Binding<String>, prompt: String, isURL: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(ANColor.mutedForeground)
            TextField(label, text: text, prompt: Text(prompt))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(isURL ? .URL : .asciiCapable)
                #endif
        }
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
#endif

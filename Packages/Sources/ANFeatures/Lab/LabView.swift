#if DEBUG
import ANCore
import ANDesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Layar lab (DEBUG saja): buat kunci, jalankan `lab_ca.py issue`, tempel JSON hasilnya.
struct LabView: View {
    let services: AppServices
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var channel: ChannelKind = .ble
    @State private var begun: (credentialID: Data, publicKey: Data)?
    @State private var json = ""
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("lab.step1")) {
                    Picker(localized("lab.channel"), selection: $channel) {
                        Text(localized("channel.ble")).tag(ChannelKind.ble)
                        Text(localized("channel.tap")).tag(ChannelKind.nfcHCE)
                    }
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
            onImported()
        } catch ANError.cardLimitReached {
            message = localized("lab.limit")
        } catch {
            message = localized("lab.failed")
        }
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
#endif

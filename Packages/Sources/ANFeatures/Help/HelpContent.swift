import ANCore

/// Topik FAQ in-app (FR-60), dalam urutan FR-60. Jawaban mengikuti perilaku R1 dan tidak menjanjikan
/// fitur yang belum ada (ADR-0048). Teks dari katalog (ID dan EN).
enum HelpTopic: String, CaseIterable, Identifiable {
    case devices, cards, limit, offline, lockedScreen, delete, members, sharing, transfer, lost

    var id: String { rawValue }

    var question: String {
        switch self {
        case .devices: localized("help.faq.devices.question")
        case .cards: localized("help.faq.cards.question")
        case .limit: localized("help.faq.limit.question")
        case .offline: localized("help.faq.offline.question")
        case .lockedScreen: localized("help.faq.lockedScreen.question")
        case .delete: localized("help.faq.delete.question")
        case .members: localized("help.faq.members.question")
        case .sharing: localized("help.faq.sharing.question")
        case .transfer: localized("help.faq.transfer.question")
        case .lost: localized("help.faq.lost.question")
        }
    }

    var answer: String {
        switch self {
        case .devices: localized("help.faq.devices.answer")
        case .cards: localized("help.faq.cards.answer")
        case .limit: localized("help.faq.limit.answer")
        case .offline: localized("help.faq.offline.answer")
        case .lockedScreen: localized("help.faq.lockedScreen.answer")
        case .delete: localized("help.faq.delete.answer")
        case .members: localized("help.faq.members.answer")
        case .sharing: localized("help.faq.sharing.answer")
        case .transfer: localized("help.faq.transfer.answer")
        case .lost: localized("help.faq.lost.answer")
        }
    }
}

enum HelpContent {
    /// Status satu cara akses di iPhone ini untuk bagian "Cara akses di iPhone ini" (FR-60 per kanal).
    static func status(for availability: ChannelAvailability?) -> String {
        switch availability {
        case .available?: localized("help.channel.available")
        case .bluetoothOff?: localized("help.channel.bluetooth_off")
        case .bluetoothUnauthorized?: localized("help.channel.bluetooth_denied")
        default: localized("help.channel.unavailable")
        }
    }
}

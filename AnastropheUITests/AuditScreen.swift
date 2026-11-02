import Foundation

/// Keadaan layar demo yang diaudit (spesifikasi audit aksesibilitas, ADR-0057). Data demo DEBUG
/// (`-ANDemo`), tanpa jaringan dan tanpa presentasi nyata.
enum AuditScreen: String, CaseIterable {
    case list, empty, detail, detailSuspended, history, presentation, bluetoothDenied, presentationDenied, help
    case add, addCode, addConfirm, addInvitation, addDone, addPending, addFailed

    /// Nilai `-ANDemoScreen`; nil = daftar kartu.
    var demoArgument: String? {
        switch self {
        case .list: nil
        case .empty: "empty"
        case .detail, .history: "detail"
        case .detailSuspended: "detail-suspended"
        case .presentation: "presentation"
        case .bluetoothDenied: "bluetooth-denied"
        case .presentationDenied: "presentation-denied"
        case .help: "help"
        case .add: "add"
        case .addCode: "add-code"
        case .addConfirm: "add-confirm"
        case .addInvitation: "add-invitation"
        case .addDone: "add-done"
        case .addPending: "add-pending"
        case .addFailed: "add-failed"
        }
    }

    /// Identifier elemen yang menandai keadaan sudah tampil.
    var marker: String {
        switch self {
        case .list: "keys.list"
        case .empty: "keys.empty.add"
        case .detail, .detailSuspended: "detail.list"
        case .history: "history.list"
        case .presentation: "present.cancel"
        case .bluetoothDenied: "present.open_settings"
        case .presentationDenied: "present.done"
        case .help: "help.list"
        case .add: "add.method.card"
        case .addCode, .addInvitation: "add.field_error"
        case .addConfirm: "add.confirm.read"
        case .addDone: "add.result.done"
        case .addPending: "add.result.pending"
        case .addFailed: "add.result.failed"
        }
    }

    /// Elemen yang diketuk sebelum penanda ditunggu: riwayat lengkap dan satu topik FAQ yang dibuka.
    var preparation: String? {
        switch self {
        case .history: "detail.history.see_all"
        case .help: "help.faq.devices"
        default: nil
        }
    }

    /// Gulir tambahan pada ukuran teks bawaan untuk layar panjang. Di AX5 setiap layar sampai 4.
    var scrollPages: Int {
        switch self {
        case .detail, .detailSuspended, .history: 2
        case .help: 3
        default: 0
        }
    }

    /// Riwayat lengkap hanya berisi baris teks; layar lain wajib punya elemen konten yang bisa diketuk.
    var hasContentTargets: Bool { self != .history }
}

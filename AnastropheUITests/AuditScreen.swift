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

    /// Identifier kontainer gulir layar (List atau ScrollView). Gulir dan sidik jari gulir memakai kontainer ini,
    /// bukan seluruh app: teks layar di belakang lembar tidak ikut, sehingga lembar tidak berhenti di halaman 1.
    /// Nil = layar tanpa kontainer gulir; gulir memakai app.
    var scrollContainer: String? {
        switch self {
        case .list: "keys.list"
        case .empty: nil
        case .detail, .detailSuspended: "detail.list"
        case .history: "history.list"
        case .help: "help.list"
        case .presentation, .bluetoothDenied, .presentationDenied: "present.scroll"
        case .add, .addCode, .addConfirm, .addInvitation, .addDone, .addPending, .addFailed: "add.scroll"
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

    /// Kontainer yang digulir untuk mencari elemen persiapan: "Lihat semua" ada di detail kartu, topik FAQ di
    /// Bantuan sendiri.
    var preparationContainer: String? {
        switch self {
        case .history: "detail.list"
        case .help: "help.list"
        default: nil
        }
    }

    /// Batas gulir tambahan pada ukuran teks bawaan untuk layar panjang; audit berhenti sendiri di ujung isi, dan test
    /// gagal bila batas habis lebih dulu. Satu gulir = 60 % tinggi kontainer. Di AX5 batasnya `AuditAX5Tests.pages`.
    var scrollPages: Int {
        switch self {
        case .detail, .detailSuspended, .history: 4
        case .help: 8
        default: 0
        }
    }

    /// Riwayat lengkap hanya berisi baris teks; layar lain wajib punya elemen konten yang bisa diketuk.
    var hasContentTargets: Bool { self != .history }

    /// Pita seret (posisi vertikal ternormalisasi di dalam kontainer gulir) tempat seretan gulir dimulai dan berakhir.
    /// Pita harus berada di atas isi yang bisa digulir: di bawah bilah navigasi (±30 % teratas daftar) dan, pada lembar
    /// presentasi, di atas tombol aksi yang tersemat di bawah (`safeAreaInset`, mulai ±57 % tinggi lembar di AX5).
    var dragBand: ClosedRange<CGFloat> {
        isPresentationSheet ? 0.12...0.5 : 0.3...0.85
    }

    /// Layar berupa lembar presentasi (`present.scroll`): di ukuran bawaan setengah tinggi dengan latar redup layar
    /// Kunci di belakangnya, di AX5 lembar penuh.
    var isPresentationSheet: Bool {
        switch self {
        case .presentation, .bluetoothDenied, .presentationDenied: true
        default: false
        }
    }
}

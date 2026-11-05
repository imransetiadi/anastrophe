import CoreGraphics
import UIKit
import XCTest

/// Varian peluncuran audit: ukuran teks AX5 dan bahasa Inggris (bawaan: ukuran sistem, bahasa ID).
struct AuditVariant: CustomStringConvertible {
    var largeText = false
    var english = false

    var description: String { [largeText ? "AX5" : nil, english ? "EN" : "ID"].compactMap(\.self).joined(separator: " ") }
}

/// Pengecualian audit per elemen (spesifikasi Tujuan 8): satu jenis audit, satu elemen yang dikenali persis, dan
/// alasan tertulis. Elemen dikenali lewat identifier atau, bila tidak punya, label persis (deretan angka diganti `#`
/// agar label berisi waktu dikenali). Pengecualian per jenis audit tidak diizinkan, jadi `identifier` atau `label`
/// wajib ada. `screens` membatasi keadaan layar tempat pengecualian berlaku (nil = semua keadaan).
struct AuditExemption {
    let type: XCUIAccessibilityAuditType
    let identifier: String?
    let label: String?
    /// Pola regex atas label mentah, untuk teks yang isinya berubah per run (tanggal dan jam data demo).
    let labelPattern: String?
    let screens: Set<AuditScreen>?
    /// Hanya di ukuran teks bawaan: buktinya adalah audit AX5 atas elemen yang sama, jadi di AX5 isunya tetap dihitung.
    let defaultSizeOnly: Bool
    let reason: String

    init(type: XCUIAccessibilityAuditType, identifier: String? = nil, label: String? = nil, labelPattern: String? = nil,
         screens: Set<AuditScreen>? = nil, defaultSizeOnly: Bool = false, reason: String) {
        precondition(identifier != nil || label != nil || labelPattern != nil,
                     "pengecualian wajib menyebut identifier, label, atau pola label elemen")
        self.type = type
        self.identifier = identifier
        self.label = label.map(Self.normalized)
        self.labelPattern = labelPattern
        self.screens = screens
        self.defaultSizeOnly = defaultSizeOnly
        self.reason = reason
    }

    /// Deretan angka diganti `#`: "Lihat semua 8" → "Lihat semua #".
    static func normalized(_ label: String) -> String {
        label.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression)
    }

    func matches(type: XCUIAccessibilityAuditType, identifier: String, label: String, screen: AuditScreen, largeText: Bool) -> Bool {
        guard self.type == type, !(defaultSizeOnly && largeText) else { return false }
        if let screens, !screens.contains(screen) { return false }
        if let expected = self.identifier, !identifier.isEmpty { return expected == identifier }
        guard !label.isEmpty else { return false }
        if let expected = self.label { return expected == Self.normalized(label) }
        if let pattern = labelPattern { return label.range(of: pattern, options: .regularExpression) != nil }
        return false
    }
}

/// Elemen milik sistem yang dikecualikan dari cek target sentuh buatan sendiri: tombol tanpa identifier dengan
/// label persis (satu entri per bahasa) dan alasan tertulis. Elemen ini tetap diaudit `hitRegion` Apple.
struct SystemElement {
    let label: String
    let reason: String
}

/// Keadaan layar yang sudah tampil. `scrolled`: langkah persiapan menggulir kontainer layar ini sendiri, jadi
/// halaman pertama sudah tergulir.
struct OpenedScreen {
    let app: XCUIApplication
    let scrolled: Bool
}

/// Teks teratas yang terlihat di kontainer gulir (label dan minY).
private struct ScrollFingerprint {
    /// Posisi baru harus bergeser lebih dari ini dari setiap halaman yang sudah diaudit. Gulir satu halaman
    /// memindah konten ratusan poin, sedangkan posisi ujung konten di lembar AX5 bergeser sampai ±45 pt sesudah
    /// audit (tinggi konten berubah), dan audit di ujung daftar bisa menggeser isi ke belakang.
    static let newPageDistance: CGFloat = 64
    /// Dua bacaan berturut-turut sejauh ini dianggap diam.
    static let settledDistance: CGFloat = 2

    let texts: [(label: String, minY: CGFloat)]
    /// Label teks yang terlihat di kontainer dan muncul tepat sekali, untuk cek kesinambungan antarhalaman.
    let uniqueLabels: Set<String>

    /// Semua teks yang terlihat (label dan minY), untuk mengukur selisih posisi antara dua tampilan yang bertumpang tindih.
    let visible: [(label: String, minY: CGFloat)]

    /// Selisih bertanda minY (tampilan ini − pembanding) pada teks yang muncul tepat sekali di keduanya: median semua
    /// selisih, agar satu label kembar yang kebetulan hanya sekali terlihat di masing-masing tampilan (status "Diizinkan"
    /// di baris riwayat yang berbeda) tidak menentukan hasil; nil bila tidak ada. Negatif: isi berada lebih ke atas, jadi
    /// sudah tergulir lebih jauh daripada pembanding.
    func offset(from other: ScrollFingerprint) -> CGFloat? {
        var deltas: [CGFloat] = []
        for text in visible where visible.filter({ $0.label == text.label }).count == 1 {
            let matches = other.visible.filter { $0.label == text.label }
            if matches.count == 1 { deltas.append(text.minY - matches[0].minY) }
        }
        return deltas.isEmpty ? nil : deltas.sorted()[deltas.count / 2]
    }

    /// Selisih bertanda minY pada semua label yang sama, juga yang muncul beberapa kali (nama gedung dan status
    /// berulang di daftar kartu): setiap pasangan kemunculan memberi satu selisih, dan nilainya yang paling
    /// sering berdekatan (±5 pt) dipakai, sehingga pasangan yang salah dari label kembar kalah suara. Nil bila
    /// tidak ada label yang sama. Cek kesinambungan memakai ini, karena label unik bisa tidak ada sama sekali
    /// pada halaman yang bertumpang tindih (daftar kartu AX5, run 2026-11-03).
    func pairedOffset(from other: ScrollFingerprint) -> CGFloat? {
        var deltas: [CGFloat] = []
        for text in visible {
            for match in other.visible where match.label == text.label {
                deltas.append(text.minY - match.minY)
            }
        }
        guard !deltas.isEmpty else { return nil }
        let sorted = deltas.sorted()
        var best = sorted[0]
        var bestCount = 0
        for delta in sorted {
            let count = sorted.filter { abs($0 - delta) <= 5 }.count
            if count > bestCount { bestCount = count; best = delta }
        }
        return best
    }

    /// Jarak vertikal (poin) ke sidik jari lain, diukur pada label yang muncul tepat sekali di keduanya; nil bila
    /// tidak ada label seperti itu (konten sudah bergeser jauh). Dua sidik jari kosong berjarak 0.
    func distance(to other: ScrollFingerprint) -> CGFloat? {
        if texts.isEmpty && other.texts.isEmpty { return 0 }
        for text in texts where texts.filter({ $0.label == text.label }).count == 1 {
            let matches = other.texts.filter { $0.label == text.label }
            if matches.count == 1 { return abs(matches[0].minY - text.minY) }
        }
        return nil
    }

    func isNew(comparedTo audited: [ScrollFingerprint]) -> Bool {
        audited.allSatisfy { (distance(to: $0) ?? .infinity) > Self.newPageDistance }
    }

    /// Dua teks teratas untuk baris log `AUDIT-POS`.
    var summary: String { texts.prefix(2).map { "\($0.label.prefix(24))@\(Int($0.minY))" }.joined(separator: ", ") }
}

/// Elemen di dalam bilah navigasi, dari snapshot bilah, untuk mengenali judul dan tombol kembali buatan sistem.
private struct BarElement {
    let type: XCUIElement.ElementType
    let identifier: String
    let label: String
    let frame: CGRect
}

/// Lebar tambahan zona kaca di bawah bilah atas (poin). Pengukuran di iPhone 17 Pro, mode terang: gradasi latar efek
/// tepi gulir terukur sampai ±8 pt di bawah bilah, sedangkan audit kontras menandai baris yang puncaknya ±21 pt di
/// bawah bilah (di bawah bayangan kapsul bilah, teks pada screenshot tetap tajam: 7,6:1). Nilai ini keputusan builder
/// dengan margin dua kali lipat dari temuan itu, dan aman terhadap pengecualian berlebih karena setiap elemen yang
/// dikecualikan wajib terbukti diaudit utuh di luar zona (`PageOutcome`).
private let scrollEdgeMargin: CGFloat = 48

/// Elemen halaman dari snapshot yang diambil SEBELUM audit. Audit Apple memperbesar teks sementara dan bisa menggeser
/// isi gulir, sehingga bingkai elemen isu (dibaca sesudahnya) bisa berbeda dari posisi saat piksel diukur; kebijakan
/// pengecualian yang bergantung pada letak memakai bingkai snapshot ini.
private struct PageElement {
    let type: XCUIElement.ElementType
    let identifier: String
    let label: String
    let frame: CGRect
    let isEnabled: Bool

    /// Kunci identitas elemen (jenis, identifier, label) untuk mencocokkan elemen isu dengan snapshot.
    var key: String { "\(type.rawValue)|\(identifier)|\(label)" }
}

/// Keadaan yang berubah selama audit satu halaman (isu tanpa elemen yang sudah dipakai, elemen yang ditunda).
private final class PageState {
    var disabledAllowanceUsed = 0
    var backdropAllowanceUsed = 0
    /// Pergeseran vertikal isi gulir akibat audit itu sendiri (poin), dihitung sekali saat pertama dibutuhkan.
    var scrollShift: CGFloat?
    /// Kunci elemen yang dikecualikan karena berada di zona kaca bilah atau hanya sebagian terlihat di tepi layar;
    /// wajib terlihat utuh (dan diaudit utuh) di halaman lain.
    var deferred: Set<String> = []
}

/// Hasil audit satu halaman untuk verifikasi lintas halaman.
struct PageOutcome {
    /// Kunci elemen yang dikecualikan di halaman ini dengan syarat diaudit utuh di halaman lain.
    let deferred: Set<String>
    /// Kunci elemen yang terlihat jernih di halaman ini tanpa pengecualian letak (lihat `AuditPage.isClearlyVisible`).
    let audited: Set<String>
    /// Audit Apple tetap habis waktu sesudah diulang (kegagalan infrastruktur, bukan temuan); hasil halaman ini kosong.
    var timedOut = false
}

/// Konteks satu halaman audit untuk kebijakan pengecualian.
private struct AuditPage {
    let context: String
    let screen: AuditScreen
    let scrolled: Bool
    /// Ukuran teks AX5: pengecualian `defaultSizeOnly` tidak berlaku.
    let largeText: Bool
    /// Bingkai bilah navigasi/toolbar terdepan; hanya diisi untuk halaman tergulir.
    let barFrames: [CGRect]
    /// Judul dan tombol kembali buatan `UINavigationBar`.
    let systemBarElements: [BarElement]
    /// Semua elemen halaman sebelum audit, dan batas layar tempat elemen terlihat.
    let elements: [PageElement]
    let screenBounds: CGRect
    /// Jumlah kontrol nonaktif yang tampil: batas isu kontras tanpa elemen yang boleh dikecualikan (WCAG 1.4.3).
    let disabledControls: Int
    /// Jumlah isu `elementDetection` tanpa elemen yang boleh dikecualikan karena teks di latar redup lembar modal.
    let backdropAllowance: Int
    let app: XCUIApplication
    let state: PageState

    /// Elemen snapshot sebelum audit dengan identitas (jenis, identifier, label) yang sama; kosong bila tidak ada.
    func candidates(type: XCUIElement.ElementType, identifier: String, label: String) -> [PageElement] {
        elements.filter { $0.type == type && $0.identifier == identifier && $0.label == label }
    }

    /// Bingkai ada di dalam layar (toleransi 1 pt), jadi elemen terlihat utuh.
    func isFullyOnScreen(_ frame: CGRect) -> Bool {
        screenBounds.insetBy(dx: -1, dy: -1).contains(frame)
    }

    /// Zona yang tercemar efek kaca bilah di halaman tergulir: dari tepi layar sampai bilah ditambah
    /// `scrollEdgeMargin` untuk bilah atas (area status bar ikut, karena isi gulir juga pudar di sana), dan sebaliknya
    /// untuk bilah bawah. Kosong di halaman yang belum digulir.
    var glassZones: [CGRect] {
        guard scrolled else { return [] }
        return barFrames.map { bar in
            if bar.midY < screenBounds.midY {
                return CGRect(x: screenBounds.minX, y: screenBounds.minY, width: screenBounds.width,
                              height: bar.maxY + scrollEdgeMargin - screenBounds.minY)
            }
            let top = bar.minY - scrollEdgeMargin
            return CGRect(x: screenBounds.minX, y: top, width: screenBounds.width, height: screenBounds.maxY - top)
        }
    }

    /// Pita layar yang terlihat jernih: layar dikurangi zona kaca.
    var clearBand: CGRect {
        var band = screenBounds
        for zone in glassZones {
            if zone.midY < band.midY {
                band = CGRect(x: band.minX, y: zone.maxY, width: band.width, height: max(0, band.maxY - zone.maxY))
            } else {
                band = CGRect(x: band.minX, y: band.minY, width: band.width, height: max(0, zone.minY - band.minY))
            }
        }
        return band
    }

    /// Elemen terlihat jernih di halaman ini: bagian di dalam pita jernih setinggi minimal setengah dari
    /// min(tinggi elemen, tinggi pita), jadi juga berlaku untuk paragraf AX5 yang lebih tinggi dari layar. Syarat
    /// "seluruhnya di dalam pita" tidak dipakai karena gulir bermomentum bisa melompati posisi itu (baris FAQ 249 pt
    /// dari y 856 ke y 161). Bila suatu elemen tetap tidak pernah memenuhi syarat ini, test gagal (`auditPages`).
    func isClearlyVisible(_ frame: CGRect) -> Bool {
        let band = clearBand
        let visible = frame.intersection(band)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return false }
        return visible.height >= min(frame.height, band.height) / 2 - 1
    }

    /// Kunci elemen yang terlihat jernih di halaman ini dan tidak dikecualikan karena letaknya: audit melihatnya tanpa
    /// menandainya, atau menandainya dan isu itu dihitung.
    var auditedKeys: Set<String> {
        Set(elements.filter { isClearlyVisible($0.frame) }.map(\.key)).subtracting(state.deferred)
    }
}

/// Audit aksesibilitas satu keadaan layar: `performAccessibilityAudit` Apple ditambah cek ukuran dan jarak
/// target sentuh sendiri (TC-UX-01, TC-UX-02, TC-UX-04; ADR-0057).
@MainActor
enum AccessibilityAudit {
    /// Semua pengecualian per elemen (spesifikasi Tujuan 8, ADR-0059). Setiap entri menyebut satu jenis audit, satu
    /// elemen (identifier atau label persis), keadaan layar, dan alasan; daftar akhirnya disalin ke QA §11.1.
    static let exemptions: [AuditExemption] = barItemExemptions + textScalingExemptions + textClippingExemptions + measuredExemptions

    /// Item bilah navigasi/toolbar app. Hanya `dynamicType`; kontras dan teks terpotong item ini tetap dihitung,
    /// kecuali lewat aturan bilah kaca di halaman tergulir.
    private static let barItemExemptions: [AuditExemption] = [
        AuditExemption(type: .dynamicType, identifier: "keys.add", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "keys.help", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "keys.lab", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "detail.lab_renew", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "help.done", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "add.back", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "add.close", reason: barItemReason),
    ]

    /// `dynamicType` di ukuran bawaan pada teks bertext style yang terbukti membesar di AX5 (screenshot AX5 keadaan
    /// yang sama; audit AX5 tidak melaporkannya). Label berisi waktu atau angka ditulis dengan `#`.
    private static let textScalingExemptions: [AuditExemption] =
        labels(.dynamicType, ["#", "Berlaku hingga", "Lihat semua", "Riwayat tap (30 hari)", "Hapus kartu"],
               screens: [.detail], reason: textScalingReason)
        // Tanggal-jam data demo (berlaku hingga dan baris riwayat) berubah setiap run: dikenali dari polanya.
        + [AuditExemption(type: .dynamicType, labelPattern: #"^[0-9]{1,2} \p{L}{3,4} [0-9]{4}, [0-9]{1,2}\.[0-9]{2}$"#,
                          screens: [.detail], defaultSizeOnly: true, reason: textScalingReason)]
        + labels(.dynamicType, ["Belum ada tap dalam 30 hari terakhir."], screens: [.detailSuspended], reason: textScalingReason)
        // Pemberitahuan ditangguhkan dan tombol Hapus kartu dilaporkan audit di KEDUA ukuran: "unsupported" di ukuran
        // bawaan dan "partially unsupported" di AX5, sedangkan screenshot elemen dari audit itu sendiri menunjukkan
        // teks tampil utuh membesar di AX5 (run 2026-11-03, diekspor ke workspace; dicatat di QA §11.1).
        + labelsAllSizes(.dynamicType, ["Kartu ini sedang ditangguhkan oleh pengelola gedung.", "Your building operator has suspended this card."],
                         screens: [.detailSuspended], reason: ax5ScalingReason)
        + labelsAllSizes(.dynamicType, ["Hapus kartu", "Delete card"], screens: [.detailSuspended], reason: ax5ScalingReason)
        + labels(.dynamicType, ["Belum ada kartu", "Tambahkan kartu akses gedung yang disetujui pengelola gedung Anda."],
                 screens: [.empty], reason: textScalingReason)
        + identifiers(.dynamicType, ["keys.empty.add"], screens: [.empty], defaultSizeOnly: true, reason: textScalingReason)
        + labels(.dynamicType, ["Bagikan laporan diagnostik"], screens: [.help], reason: textScalingReason)
        // Jawaban FAQ yang terbuka membawa identifier grupnya (`help.faq.<topik>`) sebagai teks statis.
        + identifiers(.dynamicType, ["help.faq.devices"], screens: [.help], defaultSizeOnly: true, reason: textScalingReason)

    /// `textClipped` ("mungkin terpotong di ukuran lebih besar") pada teks yang tidak punya mekanisme pemotong (lint
    /// `tanpaPemotongTeks`) dan tampil utuh di AX5 (screenshot AX5 keadaan yang sama). Daftar di ukuran bawaan saja;
    /// lembar presentasi dan field tautan di semua ukuran, karena isu yang sama muncul di AX5 dengan teks yang utuh.
    private static let textClippingExemptions: [AuditExemption] =
        labels(.textClipped, ["Hapus kartu"], screens: [.detail], reason: textClippingReason)
        + labels(.textClipped, ["Tambahkan kartu akses gedung yang disetujui pengelola gedung Anda."], screens: [.empty], reason: textClippingReason)
        // Judul daftar kosong: bukti yang sama — utuh di AX5 (screenshot AX5; audit AX5 tidak melaporkannya).
        + labels(.textClipped, ["Belum ada kartu"], screens: [.empty], reason: textClippingReason)
        + labels(.textClipped, ["Bluetooth", "Tempel ke pembaca", "Bagikan laporan diagnostik"], screens: [.help], reason: textClippingReason)
        // Lembar presentasi: judul, keterangan, dan tombolnya. Audit menandai elemen yang berbeda-beda per ukuran dan
        // bahasa, tetapi teks lembar selalu tampil utuh (screenshot AX5 ID dan EN).
        + identifiers(.textClipped, ["present.title", "present.detail", "present.retry", "present.cancel", "present.open_settings"],
                      screens: [.presentation, .bluetoothDenied, .presentationDenied], reason: sheetClippingReason)
        // Field satu baris untuk tautan: isi yang panjang bergulir mendatar di dalam field, tingginya mengikuti
        // Dynamic Type (`ANPaddedUITextField` ≥ 44 pt).
        + identifiers(.textClipped, ["add.link.field"], screens: [.addInvitation], reason: singleLineFieldReason)

    /// Kontras yang terukur dari piksel sebagai positif palsu (ADR-0059): pasangan token lolos `ContrastTests` dan
    /// piksel screenshot mengonfirmasi warna yang dirender.
    private static let measuredExemptions: [AuditExemption] = [
        AuditExemption(type: .contrast, label: "Gedung Anda", screens: [.addConfirm], reason: gedungAndaReason),
    ]

    /// Pengecualian berlabel di daftar layar selalu hanya untuk ukuran bawaan (buktinya audit AX5 atas teks yang sama).
    private static func labels(_ type: XCUIAccessibilityAuditType, _ labels: [String], screens: Set<AuditScreen>,
                               reason: String) -> [AuditExemption] {
        labels.map { AuditExemption(type: type, label: $0, screens: screens, defaultSizeOnly: true, reason: reason) }
    }

    /// Pengecualian berlabel untuk kedua ukuran teks, hanya bila audit juga keliru di AX5 (bukti screenshot elemen).
    private static func labelsAllSizes(_ type: XCUIAccessibilityAuditType, _ labels: [String], screens: Set<AuditScreen>,
                                       reason: String) -> [AuditExemption] {
        labels.map { AuditExemption(type: type, label: $0, screens: screens, reason: reason) }
    }

    private static func identifiers(_ type: XCUIAccessibilityAuditType, _ identifiers: [String], screens: Set<AuditScreen>,
                                    defaultSizeOnly: Bool = false, reason: String) -> [AuditExemption] {
        identifiers.map { AuditExemption(type: type, identifier: $0, screens: screens, defaultSizeOnly: defaultSizeOnly, reason: reason) }
    }

    static let systemElements: [SystemElement] = [
        SystemElement(label: "Pengambil Lembar", reason: grabberReason),
        SystemElement(label: "Sheet Grabber", reason: grabberReason),
    ]

    static let barItemReason = "Item bilah navigasi/toolbar di iOS tidak mengikuti Dynamic Type; sebagai gantinya sistem "
        + "menampilkan Large Content Viewer saat item ditekan lama."
    static let grabberReason = "Grabber lembar dibuat sistem untuk lembar dengan beberapa detent; ukurannya (±73 × 24 pt) "
        + "tidak bisa diatur app. Tetap diaudit hitRegion Apple."
    static let disabledContrastReason = "WCAG 1.4.3: komponen UI yang nonaktif tidak wajib memenuhi kontras."
    static let underBarReason = "Halaman tergulir: elemen (posisi sebelum audit) berada di zona kaca bilah, yaitu dari tepi "
        + "layar sampai bilah + \(Int(scrollEdgeMargin)) pt, tempat efek tepi gulir memudarkan dan mengaburkan isi sehingga "
        + "piksel yang diukur bercampur dengan bilah dan konten lain. Elemen yang sama wajib terlihat jernih di luar zona "
        + "tanpa ditandai pada halaman lain; test gagal bila tidak."
    static let systemNavigationBarReason = "Judul dan tombol kembali dibuat UINavigationBar: ukuran, batas ukuran, dan "
        + "pemotongan teksnya diatur sistem, bukan tata letak app; app hanya memberi teks judul."
    static let textScalingReason = "Teks memakai text style Dynamic Type dan membesar di AX5 tanpa terpotong (screenshot AX5 "
        + "keadaan yang sama; audit AX5 tidak melaporkannya). Audit di ukuran bawaan keliru melaporkan 'tidak didukung'."
    static let ax5ScalingReason = "Positif palsu heuristik audit pada baris daftar SwiftUI (ADR-0059): teks memakai text style "
        + "Dynamic Type dan tampil utuh membesar di AX5 — screenshot elemen dari audit itu sendiri menunjukkan teks lengkap "
        + "tanpa terpotong (diekspor dari result bundle run 2026-11-03; dicatat di QA §11.1). Audit melaporkan elemen yang "
        + "sama 'unsupported' di ukuran bawaan dan 'partially unsupported' di AX5."
    static let textClippingReason = "Teks tidak punya mekanisme pemotong (lint tanpaPemotongTeks: tanpa lineLimit, "
        + "minimumScaleFactor, truncationMode) dan tampil utuh membungkus di AX5 (screenshot AX5 keadaan yang sama). "
        + "Audit hanya menduga 'mungkin terpotong'."
    static let sheetClippingReason = textClippingReason + " Pada lembar presentasi audit menandai elemen yang berbeda per "
        + "ukuran dan bahasa, sedangkan seluruh teks lembar utuh di AX5 ID dan EN."
    static let singleLineFieldReason = "Field satu baris untuk tautan: isi yang lebih panjang dari lebar field bergulir mendatar "
        + "saat diedit (perilaku UITextField), huruf dan tinggi field mengikuti Dynamic Type (ANPaddedUITextField ≥ 44 pt, "
        + "adjustsFontForContentSizeCategory)."
    static let gedungAndaReason = "Positif palsu kontras (ADR-0059): token mutedForeground di atas background lolos "
        + "ContrastTests (7,24:1 terang) dan piksel screenshot mengukur #475569 di atas #F8FAFC = 7,24:1."
    static let partialReason = "Elemen hanya sebagian terlihat di tepi layar (bingkai sebelum audit melewati batas layar), "
        + "sehingga piksel yang diukur audit bukan teks dan latar elemen itu (screenshot elemen: sisa tepi dan area kosong). "
        + "Elemen yang sama wajib terlihat jernih tanpa ditandai di halaman lain; test gagal bila tidak."
    static let tallReason = "Elemen lebih tinggi dari pita layar yang jernih (paragraf di AX5), sehingga tidak pernah bisa "
        + "tampil utuh: audit ikut mengukur bagian di luar layar atau di bawah kaca bilah. Warnanya dijaga ContrastTests dan "
        + "audit ukuran bawaan atas teks yang sama, tata letaknya oleh screenshot AX5."
    static let backdropReason = "Lembar modal setengah tinggi: audit mendeteksi teks di latar redup layar Kunci yang sengaja "
        + "tidak terpapar ke VoiceOver selama lembar tampil. Dibatasi dua wilayah per halaman; tidak ada di lembar penuh (AX5)."

    /// Latar layar Kunci baru dianggap terlihat bila puncak lembar lebih rendah dari ini (poin).
    static let backdropVisibleMinimum: CGFloat = 150
    /// Wilayah teks latar yang terdeteksi per halaman di baseline lembar presentasi setengah tinggi.
    static let backdropRegions = 2

    /// Jenis audit yang hasilnya bergantung pada piksel/tata letak di bawah bahan kaca bilah sesudah digulir.
    /// `elementDetection` ikut, karena deteksi teks menandai piksel pudar isi gulir di bawah kaca bilah sebagai
    /// teks tak terpapar (Bantuan AX5 hlm 18+, run 2026-11-03; screenshot: teks tajam di luar zona, pudar di dalamnya).
    static let glassAffectedTypes: [XCUIAccessibilityAuditType] = [.contrast, .textClipped, .dynamicType, .elementDetection]
    /// Jenis audit yang dikecualikan untuk judul dan tombol kembali buatan sistem.
    static let systemBarTextTypes: [XCUIAccessibilityAuditType] = [.textClipped, .dynamicType]
    /// Identifier tombol kembali buatan `UINavigationBar`.
    static let backButtonIdentifier = "BackButton"

    static let minimumTarget: CGFloat = 44
    static let minimumSpacing: CGFloat = 8
    static let tolerance: CGFloat = 0.5
    static let maximumPreparationSwipes = 8

    /// Awalan identifier baris FAQ Bantuan (`DisclosureGroup` dalam `List`). Setiap baris adalah satu tombol buka-tutup
    /// selebar sel dan setinggi ≥ 44 pt, dengan penunjuk (chevron) bawaan sistem di ujungnya sebagai tombol tanpa nama
    /// (10 × 14 pt di ukuran bawaan, 32 × 45 pt di AX5). Penunjuk itu tidak bisa diatur app dan hanya menduplikasi
    /// fungsi baris; bahwa ketukan di area kosong sel membuka jawaban dibuktikan
    /// `KunciFungsionalTests.testBarisFAQDiketukDiLuarTeksMembukaJawaban`. Penunjuk tetap diaudit `hitRegion` Apple.
    static let disclosureRowPrefix = "help.faq."

    // MARK: Peluncuran

    static func launch(_ screen: AuditScreen, variant: AuditVariant) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ANDemo"]
        if let argument = screen.demoArgument { app.launchArguments += ["-ANDemoScreen", argument] }
        if variant.largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        // Bahasa selalu eksplisit: bahasa sistem simulator bisa Inggris walau wilayah pengembangan app `id`.
        app.launchArguments += variant.english ? ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] : ["-AppleLanguages", "(id)", "-AppleLocale", "id_ID"]
        app.launch()
        return app
    }

    /// Meluncurkan app pada keadaan layar lalu menunggu penandanya. Nil (dan test gagal) bila penanda tidak muncul,
    /// agar audit tidak pernah lulus atas layar yang salah atau kosong.
    static func open(_ screen: AuditScreen, variant: AuditVariant, file: StaticString = #filePath, line: UInt = #line) -> OpenedScreen? {
        let app = launch(screen, variant: variant)
        var scrolled = false
        if let preparation = screen.preparation {
            let target = element(preparation, in: app)
            let container: XCUIElement = screen.preparationContainer.map { element($0, in: app) } ?? app
            guard container.waitForExistence(timeout: 10) else {
                XCTFail("\(screen) \(variant): kontainer gulir persiapan \(screen.preparationContainer ?? "app") tidak muncul", file: file, line: line)
                return nil
            }
            // Posisi teratas sebelum gulir persiapan, sebagai tujuan pemulihan.
            let top = screen.preparationContainer == screen.scrollContainer ? settledFingerprint(container) : nil
            guard let swipes = scrollUntilHittable(target, swiping: container, band: screen.dragBand) else {
                XCTFail("\(screen) \(variant): elemen persiapan \(preparation) tidak muncul", file: file, line: line)
                return nil
            }
            target.tap()
            // Persiapan yang menggulir kontainer layar yang diaudit itu sendiri (topik FAQ di Bantuan, AX5) melewati
            // bagian atas layar. Isi dipulihkan ke posisi teratas agar audit dimulai dari awal dan bagian atas tidak
            // hanya terlihat di bawah kaca bilah. Riwayat lengkap dibuka sebagai layar baru di posisi teratas.
            if swipes > 0 && screen.preparationContainer == screen.scrollContainer, let top {
                scrolled = !restorePosition(container, to: top, at: 0, earlier: [], band: screen.dragBand, context: "\(screen) \(variant) persiapan")
                print("AUDIT-TOP | \(screen) \(variant) | kembali ke atas sesudah \(swipes) gulir persiapan | berhasil=\(!scrolled)")
            }
        }
        guard element(screen.marker, in: app).waitForExistence(timeout: 10) else {
            XCTFail("\(screen) \(variant): penanda \(screen.marker) tidak muncul", file: file, line: line)
            return nil
        }
        return OpenedScreen(app: app, scrolled: scrolled)
    }

    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Jumlah langkah gulir kontainer sampai elemen bisa diketuk, atau nil bila elemen tetap tidak bisa diketuk.
    private static func scrollUntilHittable(_ element: XCUIElement, swiping container: XCUIElement, band: ClosedRange<CGFloat>) -> Int? {
        // Baris daftar di luar layar belum ada di pohon aksesibilitas: tunggu layar dimuat, lalu gulir.
        _ = element.waitForExistence(timeout: 5)
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maximumPreparationSwipes {
            scrollStep(container, band: band)
            swipes += 1
        }
        return element.exists && element.isHittable ? swipes : nil
    }

    // MARK: Mode tampilan

    /// Kecerahan rata-rata di bawah ini dianggap mode gelap. Latar gelap token 0,01 dan latar redup lembar di atas
    /// layar terang ±0,78, jadi kedua batas jauh dari nilai nyata.
    static let darkBrightnessLimit = 0.25
    /// Kecerahan rata-rata di atas ini dianggap mode terang.
    static let lightBrightnessLimit = 0.5

    /// Kecerahan rata-rata gambar (0 = hitam, 1 = putih): luminans sRGB (tanpa linearisasi) rata-rata atas bitmap
    /// 16 × 16. Nil bila gambar tidak bisa digambar ulang.
    static func averageBrightness(of image: UIImage) -> Double? {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return total / Double(side * side) / 255
    }

    /// Mode terang/gelap harus benar-benar aktif sebelum audit: di run RED pertama semua screenshot "gelap" ternyata
    /// terang, sehingga hasil gelap run itu tidak sah. Menyetel `XCUIDevice.appearance` saja tidak cukup, jadi
    /// kecerahan rata-rata screenshot diperiksa. Gagal (dan false) bila tidak sesuai atau tidak terbaca, agar audit
    /// tidak pernah lulus atas mode yang salah.
    @discardableResult
    static func verifyAppearance(_ app: XCUIApplication, expected: XCUIDevice.Appearance, context: String,
                                 file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let label = expected == .dark ? "gelap" : "terang"
        guard let brightness = averageBrightness(of: app.screenshot().image) else {
            XCTFail("\(context): kecerahan screenshot tidak bisa dihitung, mode \(label) tidak terverifikasi", file: file, line: line)
            return false
        }
        let matches = expected == .dark ? brightness < darkBrightnessLimit : brightness > lightBrightnessLimit
        print("AUDIT-MODE | \(context) | diharapkan=\(label) | kecerahan=\(String(format: "%.3f", brightness)) | sesuai=\(matches)")
        if !matches {
            XCTFail("\(context): mode \(label) tidak aktif (kecerahan rata-rata \(String(format: "%.2f", brightness))); hasil audit tidak sah",
                    file: file, line: line)
        }
        return matches
    }

    // MARK: Audit

    /// Audit dan cek target sentuh di halaman pertama, lalu sesudah setiap gulir kontainer layar sampai `pages`
    /// habis atau gulir tidak lagi membawa ke posisi baru.
    static func auditPages(_ opened: OpenedScreen, screen: AuditScreen, context: String, pages: Int, largeText: Bool = false,
                           file: StaticString = #filePath, line: UInt = #line) {
        let app = opened.app
        let container = pages > 0 ? scrollContainer(of: screen, in: app, context: context, file: file, line: line) : nil
        // Posisi setiap halaman dicatat sebelum diaudit. Audit Apple sendiri bisa menggeser isi daftar (terlihat di
        // ujung konten pada AX5), jadi halaman baru harus berbeda dari semua posisi yang sudah diaudit, bukan hanya
        // dari posisi sesudah audit terakhir.
        var audited = container.map { [settledFingerprint($0)] } ?? []
        // Posisi isi setiap halaman yang diaudit (poin dari halaman 1, positif = lebih jauh ke bawah), dari selisih teks
        // yang sama antara halaman berurutan. Dipakai untuk kembali ke halaman yang jauh sesudah audit mengembalikan
        // daftar ke puncak isi (`restorePosition`).
        var positions: [CGFloat] = audited.isEmpty ? [] : [0]
        if let first = audited.first { print("AUDIT-POS | \(context) hlm 1 | \(first.summary)") }
        var checked = 0
        var deferred: Set<String> = []
        var auditedWhole: Set<String> = []
        // Cek target sentuh dijalankan sebelum audit Apple di setiap halaman: audit memperbesar teks sementara dan bisa
        // menggeser isi gulir, sehingga sesudahnya tombol yang terlihat di screenshot halaman itu bisa tidak lagi
        // terjangkau (tombol "Selesai" layar Menunggu di AX5 terlihat penuh tetapi tidak terhitung).
        func auditPage(_ number: Int, scrolled: Bool) {
            let name = "\(context) hlm \(number)"
            checked += checkTouchTargets(app, context: name, file: file, line: line)
            var outcome = audit(app, screen: screen, context: name, scrolled: scrolled, largeText: largeText,
                                failOnTimeout: container == nil, file: file, line: line)
            if outcome.timedOut, let container {
                // Audit Apple bisa tetap habis waktu di satu posisi gulir walau diulang: riwayat AX5 hlm 2 (posisi 454 pt)
                // di iPhone 17e gagal di tiga run 2026-11-03/04, sedangkan semua posisi lain dan iPhone 17 Pro lulus.
                // Isi digeser `nudgeDistance` lalu halaman diaudit sekali lagi sebagai halaman tergulir; halaman
                // berurutan tetap bertumpang tindih, dan posisi dipulihkan sesudahnya. Gagal bila tetap habis waktu.
                drag(container, by: -nudgeDistance, band: screen.dragBand)
                print("AUDIT-NUDGE | \(name) | isi digeser \(Int(nudgeDistance)) pt sesudah audit habis waktu")
                outcome = audit(app, screen: screen, context: "\(name) geser", scrolled: true, largeText: largeText,
                                file: file, line: line)
            }
            deferred.formUnion(outcome.deferred)
            auditedWhole.formUnion(outcome.audited)
            guard let container, let before = audited.last, let position = positions.last else { return }
            // Audit Dynamic Type mengubah ukuran teks sementara, dan sesudahnya isi gulir bisa berada di posisi lain
            // (Bantuan AX5 melompat ±1.000 pt, dan dari halaman 11 kembali ke puncak isi; run 2026-11-03), sehingga gulir
            // berikutnya melewati isi yang belum diaudit. Posisi dipulihkan ke posisi halaman ini sebelum gulir berikutnya.
            let after = settledFingerprint(container)
            print("AUDIT-POS-SESUDAH | \(name) | \(after.summary)")
            let drift = after.offset(from: before) ?? after.pairedOffset(from: before)
            if (drift.map(abs) ?? .infinity) > restoreTolerance {
                let earlier = zip(audited, positions).dropLast().map { (fingerprint: $0.0, position: $0.1) }
                // Tanpa pemulihan, gulir berikutnya bisa kembali ke halaman yang sudah diaudit dan audit berhenti
                // seolah sampai di ujung isi, sehingga sisa isi tidak pernah diaudit.
                if !restorePosition(container, to: before, at: position, earlier: earlier, band: screen.dragBand, context: name) {
                    XCTFail("\(name): posisi isi tidak bisa dipulihkan sesudah audit; sisa isi bisa terlewat", file: file, line: line)
                }
            }
        }
        auditPage(1, scrolled: opened.scrolled)
        if let container {
            var reachedEnd = false
            for page in 2...(pages + 1) {
                guard let previous = audited.last,
                      let current = swipeToNewPosition(container, audited: audited, band: screen.dragBand) else {
                    reachedEnd = true
                    break
                }
                // Langkah gulir lebih pendek dari kontainer, jadi halaman berurutan selalu berbagi teks dan pergeserannya
                // tidak melebihi dua langkah. Tanpa teks yang sama atau dengan lompatan lebih jauh, isi di antaranya
                // terlewat dan tidak pernah diaudit. Label dipasangkan per kemunculan, karena label unik bisa tidak ada
                // pada halaman yang bertumpang tindih (daftar kartu AX5, run 2026-11-03).
                if let shift = current.pairedOffset(from: previous) {
                    if abs(shift) > 2 * stepLength(container, band: screen.dragBand) {
                        XCTFail("\(context) hlm \(page): isi melompat \(Int(abs(shift).rounded())) pt dari halaman sebelumnya; isi di antaranya terlewat",
                                file: file, line: line)
                    }
                } else if !current.visible.isEmpty || !previous.visible.isEmpty {
                    XCTFail("\(context) hlm \(page): tidak ada teks yang sama dengan halaman sebelumnya; isi di antaranya terlewat",
                            file: file, line: line)
                }
                audited.append(current)
                // `offset` = posisi halaman sebelumnya − posisi sekarang. Tanpa teks yang sama (sudah gagal di atas),
                // posisi diperkirakan satu langkah gulir.
                let step = current.offset(from: previous).map { -$0 } ?? stepLength(container, band: screen.dragBand)
                positions.append(positions[positions.count - 1] + step)
                print("AUDIT-POS | \(context) hlm \(page) | \(current.summary) | posisi \(Int(positions[positions.count - 1].rounded())) pt")
                auditPage(page, scrolled: true)
            }
            // Isi yang tidak pernah tampil juga tidak pernah diaudit: batas halaman tidak boleh habis sebelum ujung isi.
            if !reachedEnd && swipeToNewPosition(container, audited: audited, band: screen.dragBand) != nil {
                XCTFail("\(context): batas \(pages + 1) halaman habis sebelum ujung isi; naikkan jumlah halaman", file: file, line: line)
            }
        }
        // Di AX5 halaman pertama bisa tanpa tombol; syaratnya berlaku untuk seluruh halaman yang diaudit.
        if screen.hasContentTargets && checked == 0 {
            XCTFail("\(context): tidak ada elemen konten yang bisa diketuk untuk diperiksa", file: file, line: line)
        }
        // Elemen yang dikecualikan karena berada di zona kaca bilah atau hanya sebagian terlihat di tepi layar harus
        // terlihat jernih tanpa ditandai di halaman lain. Elemen yang benar-benar gagal ditandai di halaman mana pun,
        // jadi tetap gagal di sini. Batas: untuk identitas kembar (empat tombol "Gunakan") cukup salah satunya.
        for key in deferred.subtracting(auditedWhole).sorted() {
            XCTFail("\(context): elemen \(key) hanya ditandai saat di zona kaca bilah atau sebagian di tepi layar dan tidak pernah terlihat jernih tanpa ditandai", file: file, line: line)
        }
    }

    /// Kontainer gulir layar, atau app bila layar tidak punya kontainer. Nil (dan test gagal) bila kontainer yang
    /// seharusnya ada tidak ditemukan, agar halaman berikutnya tidak terlewat diam-diam.
    private static func scrollContainer(of screen: AuditScreen, in app: XCUIApplication, context: String,
                                        file: StaticString, line: UInt) -> XCUIElement? {
        guard let identifier = screen.scrollContainer else { return app }
        let container = element(identifier, in: app)
        guard container.waitForExistence(timeout: 5) else {
            XCTFail("\(context): kontainer gulir \(identifier) tidak ditemukan", file: file, line: line)
            return nil
        }
        return container
    }

    /// Label dan posisi enam teks teratas yang terlihat di dalam kontainer; tidak berubah bila gulir sudah sampai
    /// ujung. Diambil dari kontainer itu sendiri, karena `app.staticTexts` ikut memuat teks layar di belakang
    /// lembar. Hanya teks di dalam bingkai kontainer, karena sel di luar layar yang disiapkan daftar bisa
    /// berganti tanpa gulir.
    private static func fingerprint(_ container: XCUIElement) -> ScrollFingerprint {
        let texts: [(label: String, frame: CGRect)]
        let visible: CGRect
        if let snapshot = try? container.snapshot() {
            var collected: [(label: String, frame: CGRect)] = []
            collectTexts(in: snapshot, into: &collected)
            texts = collected
            visible = snapshot.frame
        } else {
            // Kontainer bisa hilang di tengah pengukuran (lembar tertutup gestur): sidik jari kosong, agar logika
            // pemulihan yang menanganinya yang bicara, bukan galat query yang menghentikan test.
            guard container.exists else {
                return ScrollFingerprint(texts: [], uniqueLabels: [], visible: [])
            }
            texts = container.descendants(matching: .staticText).allElementsBoundByIndex.map { ($0.label, $0.frame) }
            visible = container.frame
        }
        let shown = texts.filter { $0.frame.intersects(visible) && !$0.label.isEmpty }
        let top = shown.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.prefix(6)
        let counts = Dictionary(grouping: shown, by: \.label).mapValues(\.count)
        return ScrollFingerprint(texts: top.map { (label: $0.label, minY: $0.frame.minY) },
                                 uniqueLabels: Set(counts.filter { $0.value == 1 }.keys),
                                 visible: shown.map { (label: $0.label, minY: $0.frame.minY) })
    }

    private static func collectTexts(in snapshot: XCUIElementSnapshot, into texts: inout [(label: String, frame: CGRect)]) {
        for child in snapshot.children {
            if child.elementType == .staticText { texts.append((child.label, child.frame)) }
            collectTexts(in: child, into: &texts)
        }
    }

    /// Menggulir ke posisi yang belum diaudit dan memberi sidik jarinya, atau nil bila konten sudah di ujung. Saat
    /// simulator sibuk satu gulir bisa tertelan tanpa gerak, jadi ujung konten baru disimpulkan sesudah gulir kedua
    /// juga tidak membawa ke posisi baru.
    private static func swipeToNewPosition(_ container: XCUIElement, audited: [ScrollFingerprint], band: ClosedRange<CGFloat>) -> ScrollFingerprint? {
        for _ in 0..<2 {
            scrollStep(container, band: band)
            var current = settledFingerprint(container)
            if current.texts.isEmpty {
                // Isi kosong berarti gulir atau audit menyeret daftar melewati ujung isi (Bantuan AX5, run
                // 2026-11-03): tarik mundur sampai isi tampil lagi sebelum menyimpulkan apa pun.
                for _ in 0..<6 where current.texts.isEmpty {
                    scrollStep(container, band: band, forward: false)
                    current = settledFingerprint(container)
                }
            }
            if current.isNew(comparedTo: audited) { return current }
            // Gulir pendek di dekat ujung isi memindah konten lebih kecil dari ambang halaman baru, tetapi tetap
            // membawa isi yang belum diaudit (tombol Hapus kartu di detailSuspended AX5 ID tersisa ±40 pt,
            // run 2026-11-03). Diukur dari halaman terakhir, bukan ambang halaman baru.
            if let last = audited.last, (current.distance(to: last) ?? .infinity) > restoreTolerance {
                return current
            }
        }
        return nil
    }

    /// Selisih posisi (poin) yang dianggap sudah pulih. Seretan terkendali kehilangan ambang gerak gestur gulir (±10 pt),
    /// jadi pemulihan tidak lebih presisi dari itu; langkah gulir tetap menyisakan tumpang tindih yang jauh lebih besar.
    static let restoreTolerance: CGFloat = 24

    /// Memulihkan isi gulir ke posisi `expected` (posisi isi `position`, poin dari halaman 1) dengan seretan terkendali,
    /// tanpa pernah menggulir melewati puncak isi: gulir ke bawah di puncak lembar bisa menutup lembar.
    /// - Teks yang sama dengan `expected`: seretan sejauh selisihnya.
    /// - Teks yang sama dengan halaman yang lebih awal (`earlier`, dengan posisinya): posisi sekarang dihitung dari
    ///   halaman itu, lalu satu seretan sejauh selisih ke `position`. Audit bisa mengembalikan daftar ke puncak isi
    ///   (Bantuan AX5 dari halaman 11, run 2026-11-03); langkah gulir satu per satu tidak pernah sampai kembali.
    /// - Tanpa teks yang sama dengan halaman mana pun: wilayah yang belum diaudit, yang selalu di depan, jadi satu
    ///   langkah mundur.
    ///
    /// true bila pulih; bila tidak, cek kesinambungan halaman berikutnya menangkap isi yang terlewat.
    @discardableResult
    private static func restorePosition(_ container: XCUIElement, to expected: ScrollFingerprint, at position: CGFloat,
                                        earlier: [(fingerprint: ScrollFingerprint, position: CGFloat)],
                                        band: ClosedRange<CGFloat>, context: String) -> Bool {
        for attempt in 1...25 {
            let now = settledFingerprint(container)
            if let offset = now.offset(from: expected) {
                if abs(offset) <= restoreTolerance {
                    print("AUDIT-RESTORE | \(context) | pulih, selisih \(Int(offset.rounded())) pt sesudah \(attempt - 1) seretan")
                    return true
                }
                // Isi lebih ke atas (offset negatif) → seret jari ke bawah sejauh selisihnya, dan sebaliknya.
                drag(container, by: capped(-offset), band: band)
            } else if let known = earlier.last(where: { now.offset(from: $0.fingerprint) != nil }),
                      let offset = now.offset(from: known.fingerprint) {
                let current = known.position - offset
                print("AUDIT-RESTORE | \(context) | di posisi ±\(Int(current.rounded())) pt, tujuan \(Int(position.rounded())) pt")
                // Posisi tujuan lebih jauh → jari ke atas (jarak negatif).
                drag(container, by: capped(current - position), band: band)
            } else if now.texts.isEmpty {
                // Isi kosong berarti daftar terseret melewati ujung isi sesudah audit (Bantuan dan detail AX5,
                // run 2026-11-03): dua bacaan pertama menunggu gambar ulang, sesudahnya isi ditarik kembali
                // dengan seretan mundur seperti yang dilakukan pengguna.
                if attempt > 2 { scrollStep(container, band: band, forward: false) }
            } else {
                scrollStep(container, band: band, forward: false)
            }
        }
        print("AUDIT-RESTORE | \(context) | tidak pulih sesudah 25 seretan | \(settledFingerprint(container).summary)")
        return false
    }

    /// Panjang maksimum satu seretan pemulihan (poin): maju 500, mundur 100. Seretan mundur yang melampaui puncak
    /// isi lembar bisa menutup lembar itu (Tambah Kartu AX5, run 2026-11-03), jadi tetap pendek. Seretan maju tidak
    /// bisa menutup lembar; sesudah audit daftar panjang kembali ke dekat puncak (Bantuan AX5: tujuan 7.301 pt dari
    /// posisi 1.700 pt), sehingga langkah maju yang pendek tidak sampai dalam jumlah percobaan yang tersedia.
    /// Posisi selalu diukur ulang di antara seretan, jadi langkah besar yang melampaui tujuan terkoreksi.
    static let maximumForwardDrag: CGFloat = 500
    static let maximumBackwardDrag: CGFloat = 100

    /// Jarak seretan dibatasi `maximumForwardDrag`/`maximumBackwardDrag`. Positif = jari ke bawah (isi turun).
    private static func capped(_ distance: CGFloat) -> CGFloat {
        distance < 0 ? max(distance, -maximumForwardDrag) : min(distance, maximumBackwardDrag)
    }

    /// Perkiraan jarak isi satu `scrollStep` (poin): panjang pita seret dikurangi ambang gerak gulir (±10 pt).
    private static func stepLength(_ container: XCUIElement, band: ClosedRange<CGFloat>) -> CGFloat {
        (band.upperBound - band.lowerBound) * container.frame.height - 10
    }

    /// Seretan terpendek (poin), jauh di atas ambang gerak gulir (±10 pt). Seretan yang lebih pendek terbaca sebagai
    /// ketukan pada baris di bawah jari: seretan 9 pt membuka "Lihat semua" di detail AX5 (run 2026-11-03).
    static let minimumDrag: CGFloat = 32

    /// Geseran isi (poin) sebelum audit diulang di posisi lain sesudah tetap habis waktu (`auditPages`): di atas
    /// `minimumDrag`, jauh di bawah satu langkah gulir, sehingga isi halaman hampir sama.
    static let nudgeDistance: CGFloat = 48

    /// Satu langkah gulir terkendali: seret sepanjang pita seret layar lalu tahan sebelum dilepas, sehingga tanpa
    /// momentum. Langkah ini lebih pendek dari pita jernih halaman tergulir, jadi setiap elemen pernah terlihat jernih di
    /// salah satu halaman. `swipeUp()` biasa bermomentum dan bisa melompati isi sepanjang lebih dari satu layar (baris
    /// FAQ AX5 tidak pernah tampil, run 2026-11-03).
    private static func scrollStep(_ container: XCUIElement, band: ClosedRange<CGFloat>, forward: Bool = true) {
        let low = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: band.upperBound))
        let high = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: band.lowerBound))
        let (start, end) = forward ? (low, high) : (high, low)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Seretan terkendali sejauh `distance` poin (positif = jari ke bawah, isi turun) di dalam pita seret, dibagi rata
    /// bila lebih panjang dari pita, dengan setiap bagian minimal `minimumDrag`.
    private static func drag(_ container: XCUIElement, by distance: CGFloat, band: ClosedRange<CGFloat>) {
        let height = container.frame.height
        guard height > 0, distance != 0 else { return }
        let span = (band.upperBound - band.lowerBound) * height
        let parts = max(1, Int((abs(distance) / span).rounded(.up)))
        let length = max(minimumDrag, abs(distance) / CGFloat(parts))
        let part = (distance < 0 ? -length : length) / height
        let startY = part > 0 ? band.lowerBound : band.upperBound
        for _ in 0..<parts {
            let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY + part))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// Sidik jari sesudah isi kontainer diam dan tampil: gulir momentum atau pantulan di ujung konten bisa masih berjalan
    /// sesudah gulir kembali, dan sesudah audit Dynamic Type daftar sempat kosong beberapa detik selagi digambar ulang
    /// (Bantuan dan detail AX5, run 2026-11-03). Tampilan tanpa teks baru diterima bila tetap kosong ±6 dtk.
    private static func settledFingerprint(_ container: XCUIElement) -> ScrollFingerprint {
        var last = fingerprint(container)
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.3)
            let current = fingerprint(container)
            if !current.texts.isEmpty, let moved = current.distance(to: last), moved <= ScrollFingerprint.settledDistance {
                return current
            }
            last = current
        }
        return last
    }

    /// `scrolled`: halaman sesudah digulir, sehingga sebagian konten berada di bawah bahan kaca bilah sistem.
    /// `failOnTimeout`: false = audit yang tetap habis waktu tidak menggagalkan test, tetapi dilaporkan lewat
    /// `PageOutcome.timedOut` agar pemanggil mengulang di posisi lain.
    @discardableResult
    static func audit(_ app: XCUIApplication, screen: AuditScreen, context: String, scrolled: Bool, largeText: Bool = false,
                      failOnTimeout: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> PageOutcome {
        attachScreenshot(of: app, named: context)
        // Snapshot SEBELUM audit: posisi saat piksel diukur (lihat `PageElement`).
        let snapshot = pageSnapshot(app)
        let disabled = snapshot.elements.filter { [.button, .link, .textField].contains($0.type) && !$0.isEnabled }.count
        let page = AuditPage(context: context, screen: screen, scrolled: scrolled, largeText: largeText, barFrames: scrolled ? frontBarFrames(app) : [],
                             systemBarElements: systemNavigationBarElements(app), elements: snapshot.elements,
                             screenBounds: snapshot.bounds, disabledControls: disabled,
                             backdropAllowance: backdropAllowance(for: screen, elements: snapshot.elements, bounds: snapshot.bounds),
                             app: app, state: PageState())
        // Baris halaman dan isu dihitung untuk bukti QA (jumlah halaman, temuan per jenis dan per keadaan).
        print("AUDIT-PAGE | \(context) | scrolled=\(scrolled) | bars=\(page.barFrames.map { describe($0) }) | nonaktif=\(disabled) | latar=\(page.backdropAllowance)")
        do {
            try performAudit(app, page: page)
        } catch let error as NSError where !failOnTimeout && isAuditTimeout(error) {
            print("AUDIT-TIMEOUT | \(context) | \(error.localizedDescription)")
            return PageOutcome(deferred: [], audited: [], timedOut: true)
        } catch {
            XCTFail("\(context): audit tidak bisa dijalankan: \(error)", file: file, line: line)
        }
        return PageOutcome(deferred: page.state.deferred, audited: page.auditedKeys)
    }

    /// Snapshot seluruh app: elemen dengan jenis, identifier, label, bingkai, dan status aktif, serta batas layar
    /// (bingkai akar aplikasi). Kosong bila snapshot gagal; pemanggil lalu memakai bingkai elemen isu apa adanya.
    private static func pageSnapshot(_ app: XCUIApplication) -> (elements: [PageElement], bounds: CGRect) {
        guard let snapshot = try? app.snapshot() else { return ([], app.frame) }
        var elements: [PageElement] = []
        collectPageElements(in: snapshot, into: &elements)
        return (elements, snapshot.frame)
    }

    private static func collectPageElements(in snapshot: XCUIElementSnapshot, into elements: inout [PageElement]) {
        for child in snapshot.children {
            elements.append(PageElement(type: child.elementType, identifier: child.identifier, label: child.label,
                                        frame: child.frame, isEnabled: child.isEnabled))
            collectPageElements(in: child, into: &elements)
        }
    }

    /// Dua wilayah teks di latar redup lembar presentasi setengah tinggi terdeteksi `elementDetection` sebagai teks tak
    /// terpapar (tercatat di baseline). Latar itu layar Kunci di belakang lembar modal, yang sengaja tidak terpapar ke
    /// VoiceOver selama lembar tampil. Di lembar penuh (AX5) tidak ada latar yang terlihat, jadi batasnya 0.
    private static func backdropAllowance(for screen: AuditScreen, elements: [PageElement], bounds: CGRect) -> Int {
        guard screen.isPresentationSheet, let sheet = elements.first(where: { $0.identifier == "present.scroll" }) else { return 0 }
        return sheet.frame.minY > backdropVisibleMinimum ? backdropRegions : 0
    }

    /// Lintasan audit: kontras lebih dulu, lalu semua jenis lain. Bersama-sama mencakup `.all`. Audit Dynamic Type dan
    /// teks terpotong memperbesar teks sementara dan bisa menggeser isi gulir (±100 pt di Bantuan, run 2026-11-03).
    /// Kontras yang diukur sesudah pergeseran itu membaca piksel di posisi lain daripada bingkai elemennya, sehingga teks
    /// bertoken yang tajam dilaporkan gagal. Kontras sendirian tidak mengubah tata letak.
    static let auditPasses: [XCUIAccessibilityAuditType] = [.contrast, XCUIAccessibilityAuditType.all.subtracting(.contrast)]

    private static func performAudit(_ app: XCUIApplication, page: AuditPage) throws {
        for types in auditPasses {
            page.state.scrollShift = nil
            try performPass(app, types: types, page: page)
            if types == .contrast { print("AUDIT-SHIFT | \(page.context) | sesudah kontras | \(scrollShift(on: page)) pt") }
        }
    }

    /// Audit Apple kadang berhenti dengan "Audit failed to complete in time" (kode -56) pada daftar panjang di AX5, dan
    /// saat mesin sibuk futurnya sendiri bisa habis waktu (XCTFuture 1000). Keduanya kegagalan infrastruktur, bukan
    /// temuan: audit diulang sampai dua kali (riwayat AX5 hlm 2 gagal dua kali berturut-turut lalu lulus, run
    /// 2026-11-03), lalu gagal bila tetap tidak selesai.
    private static func performPass(_ app: XCUIApplication, types: XCUIAccessibilityAuditType, page: AuditPage) throws {
        for attempt in 0...2 {
            do {
                try app.performAccessibilityAudit(for: types) { evaluate($0, on: page) }
                return
            } catch let error as NSError where isAuditTimeout(error) && attempt < 2 {
                print("AUDIT-RETRY | \(page.context) | \(error.localizedDescription)")
            }
        }
    }

    private static func isAuditTimeout(_ error: NSError) -> Bool {
        (error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56)
            || (error.domain == "com.apple.dt.XCTest.XCTFuture" && error.code == 1000)
    }

    /// Kebijakan pengecualian (spesifikasi Tujuan 8, ADR-0057). true = isu tidak menggagalkan test; setiap isu
    /// dicetak dengan awalan sesuai keputusannya.
    private static func evaluate(_ issue: XCUIAccessibilityAuditIssue, on page: AuditPage) -> Bool {
        let type = name(of: issue.auditType)
        let detail = issue.detailedDescription.replacingOccurrences(of: "\n", with: " ")
        guard let element = issue.element, element.exists else {
            return evaluateWithoutElement(issue, type: type, detail: detail, on: page)
        }
        if let reason = exemptionReason(for: issue, element: element, on: page) {
            print("AUDIT-EXEMPT | \(page.context) | \(type) | \(issue.compactDescription) | \(describe(element)) | \(reason)")
            return true
        }
        print("AUDIT-ISSUE | \(page.context) | \(type) | \(issue.compactDescription) | \(describe(element)) | \(detail)")
        return false
    }

    /// Isu tanpa elemen tidak bisa dicek letaknya. Hanya tiga kasus sempit yang dilewati, masing-masing dibatasi
    /// jumlah yang bisa dibuktikan dari keadaan halaman; selebihnya gagal.
    private static func evaluateWithoutElement(_ issue: XCUIAccessibilityAuditIssue, type: String, detail: String,
                                               on page: AuditPage) -> Bool {
        let state = page.state
        // Kontras tombol nonaktif datang tanpa elemen: dikecualikan WCAG 1.4.3, sebanyak kontrol nonaktif yang tampil.
        if issue.auditType == .contrast && state.disabledAllowanceUsed < page.disabledControls {
            state.disabledAllowanceUsed += 1
            print("AUDIT-EXEMPT | \(page.context) | \(type) | \(issue.compactDescription) | - | \(disabledContrastReason) "
                + "(isu tanpa elemen \(state.disabledAllowanceUsed) dari \(page.disabledControls) kontrol nonaktif)")
            return true
        }
        // Teks di latar redup lembar modal setengah tinggi: dibatasi `backdropRegions` per halaman.
        if issue.auditType == .elementDetection && state.backdropAllowanceUsed < page.backdropAllowance {
            state.backdropAllowanceUsed += 1
            print("AUDIT-EXEMPT | \(page.context) | \(type) | \(issue.compactDescription) | - | \(backdropReason) "
                + "(isu \(state.backdropAllowanceUsed) dari \(page.backdropAllowance))")
            return true
        }
        // Di halaman tergulir, isu dari jenis yang terpengaruh bahan kaca hanya dicetak untuk dihitung; di halaman
        // yang belum digulir semuanya gagal.
        if page.scrolled && glassAffectedTypes.contains(issue.auditType) {
            print("AUDIT-SKIP | \(page.context) | \(type) | \(issue.compactDescription) | \(detail)")
            return true
        }
        print("AUDIT-ISSUE | \(page.context) | \(type) | \(issue.compactDescription) | - | \(detail)")
        return false
    }

    /// Alasan pengecualian isu yang punya elemen, atau nil bila isu dihitung.
    private static func exemptionReason(for issue: XCUIAccessibilityAuditIssue, element: XCUIElement, on page: AuditPage) -> String? {
        let type = issue.auditType
        if type == .contrast && !element.isEnabled { return disabledContrastReason }
        let identifier = element.identifier
        let label = element.label
        let elementType = element.elementType
        if glassAffectedTypes.contains(type) {
            // Letak diukur dari snapshot sebelum audit; bingkai elemen isu sendiri dibaca sesudah audit dan bisa sudah
            // bergeser. Bila identitas elemen kembar, pengecualian hanya berlaku bila semua kembarannya memenuhi syarat.
            let frames = measuredFrames(of: element, on: page)
            let zones = page.glassZones
            let key = "\(elementType.rawValue)|\(identifier)|\(label)"
            // Elemen yang lebih tinggi dari pita jernih (paragraf AX5) tidak pernah bisa tampil utuh, jadi tidak wajib
            // terlihat jernih di halaman lain; alasannya dicetak tersendiri dan dihitung di QA.
            let tall = frames.allSatisfy { $0.height > page.clearBand.height }
            // Cukup salah satu posisi yang mungkin: pengecualian letak selalu ditunda, dan elemen itu wajib terlihat
            // jernih tanpa ditandai di halaman lain (`auditPages`), jadi elemen yang benar-benar gagal tetap gagal.
            if !zones.isEmpty && frames.contains(where: { frame in zones.contains { $0.intersects(frame) } }) {
                // Item bilah itu sendiri selalu di dalam bilah, jadi tidak pernah terlihat di luar zona; konten yang
                // lewat di bawah bilah wajib terbukti terlihat jernih di halaman lain.
                let isBarItem = frames.allSatisfy { frame in page.barFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) } }
                if tall { return tallReason }
                if !isBarItem { page.state.deferred.insert(key) }
                return underBarReason
            }
            if frames.contains(where: { !page.isFullyOnScreen($0) }) {
                if tall { return tallReason }
                page.state.deferred.insert(key)
                return partialReason
            }
        }
        if let exemption = exemptions.first(where: {
            $0.matches(type: type, identifier: identifier, label: label, screen: page.screen, largeText: page.largeText)
        }) {
            return exemption.reason
        }
        if systemBarTextTypes.contains(type) && isSystemNavigationBarElement(element, in: page.systemBarElements) {
            return systemNavigationBarReason
        }
        return nil
    }

    /// Bingkai yang mungkin menjadi posisi elemen isu saat diukur: bingkai sebelum audit (snapshot) dan bingkai sekarang,
    /// karena lintasan jenis lain bisa menggeser isi gulir sebelum mengukur. Identitas kembar (mis. empat tombol
    /// "Gunakan"): kandidat snapshot yang paling dekat dengan bingkai sekarang, dengan pergeseran gulir dikoreksi (bilah
    /// tidak ikut bergeser, jadi jarak tanpa koreksi juga dipertimbangkan).
    private static func measuredFrames(of element: XCUIElement, on page: AuditPage) -> [CGRect] {
        let current = element.frame
        let candidates = page.candidates(type: element.elementType, identifier: element.identifier, label: element.label)
        guard candidates.count > 1 else { return (candidates.map(\.frame) + [current]) }
        let now = current.minY
        let shift = scrollShift(on: page)
        let best = candidates.min { lhs, rhs in
            min(abs(lhs.frame.minY - now), abs(lhs.frame.minY + shift - now)) < min(abs(rhs.frame.minY - now), abs(rhs.frame.minY + shift - now))
        }
        return (best.map { [$0.frame] } ?? []) + [current]
    }

    /// Pergeseran vertikal isi gulir antara snapshot sebelum audit dan sekarang: nilai yang paling sering muncul pada
    /// elemen berlabel unik yang bergeser lebih dari 0,5 pt; 0 bila tidak ada. Dihitung sekali per halaman.
    private static func scrollShift(on page: AuditPage) -> CGFloat {
        if let cached = page.state.scrollShift { return cached }
        let current = pageSnapshot(page.app).elements
        func unique(_ elements: [PageElement]) -> [String: CGRect] {
            Dictionary(grouping: elements, by: \.key).compactMapValues { $0.count == 1 ? $0[0].frame : nil }
        }
        let before = unique(page.elements)
        var counts: [Int: Int] = [:]
        for (key, frame) in unique(current) {
            guard let old = before[key] else { continue }
            let delta = frame.minY - old.minY
            if abs(delta) > 0.5 { counts[Int(delta.rounded()), default: 0] += 1 }
        }
        let shift = counts.max { $0.value < $1.value }.map { CGFloat($0.key) } ?? 0
        page.state.scrollShift = shift
        print("AUDIT-SHIFT | \(page.context) | \(shift) pt")
        return shift
    }

    /// Bilah navigasi dan toolbar yang tampil paling depan. Bilah layar di belakang lembar tetap ada di pohon
    /// aksesibilitas, tetapi tertutup lembar: bilah itu tidak menutupi konten lembar dan tombolnya tidak bisa
    /// diketuk, jadi tidak dihitung.
    private static func frontBarFrames(_ app: XCUIApplication) -> [CGRect] {
        (app.navigationBars.allElementsBoundByIndex + app.toolbars.allElementsBoundByIndex)
            .filter { bar in bar.exists && (bar.isHittable || bar.buttons.allElementsBoundByIndex.contains { $0.isHittable }) }
            .map(\.frame)
    }

    /// Judul (teks statis) dan tombol kembali (`BackButton`, atau tombol tanpa identifier) di dalam bilah
    /// navigasi. Item toolbar app selalu punya identifier sendiri, jadi tidak termasuk.
    private static func systemNavigationBarElements(_ app: XCUIApplication) -> [BarElement] {
        var elements: [BarElement] = []
        for bar in app.navigationBars.allElementsBoundByIndex {
            guard let snapshot = try? bar.snapshot() else { continue }
            collectBarElements(in: snapshot, into: &elements)
        }
        return elements.filter {
            $0.type == .staticText || ($0.type == .button && ($0.identifier.isEmpty || $0.identifier == backButtonIdentifier))
        }
    }

    private static func collectBarElements(in snapshot: XCUIElementSnapshot, into elements: inout [BarElement]) {
        for child in snapshot.children {
            elements.append(BarElement(type: child.elementType, identifier: child.identifier, label: child.label, frame: child.frame))
            collectBarElements(in: child, into: &elements)
        }
    }

    /// Elemen isu sama persis (jenis, identifier, label, bingkai) dengan judul atau tombol kembali di snapshot
    /// bilah navigasi. Konten yang hanya bertumpuk dengan bilah tidak cocok.
    private static func isSystemNavigationBarElement(_ element: XCUIElement, in barElements: [BarElement]) -> Bool {
        guard !barElements.isEmpty else { return false }
        let type = element.elementType
        let identifier = element.identifier
        let label = element.label
        let frame = element.frame
        return barElements.contains {
            $0.type == type && $0.identifier == identifier && $0.label == label
                && abs($0.frame.minX - frame.minX) <= 1 && abs($0.frame.minY - frame.minY) <= 1
                && abs($0.frame.width - frame.width) <= 1 && abs($0.frame.height - frame.height) <= 1
        }
    }

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "jenis \(type.rawValue)"
        }
    }

    private static func describe(_ element: XCUIElement?) -> String {
        guard let element, element.exists else { return "-" }
        return "tipe \(element.elementType.rawValue) id=\(element.identifier) label=\(element.label) frame=\(element.frame)"
    }

    private static func describe(_ frame: CGRect) -> String {
        "(\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)))"
    }

    private static func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Screenshot \(name)") { $0.add(attachment) }
    }

    // MARK: Target sentuh

    /// Bingkai sel baris FAQ: sel setinggi ≥ 44 pt yang memuat titik tengah tombol baris (identifier `help.faq.*`).
    /// Bingkai tombol baris bisa hanya setinggi teksnya (baris satu baris ±20 pt), jadi ukuran diambil dari sel. Penunjuk
    /// buka-tutup sistem hanya dikecualikan bila berada di dalam salah satu sel ini.
    private static func faqRowCells(_ app: XCUIApplication, cellFrames: [CGRect]) -> [CGRect] {
        let rows = app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.identifier.hasPrefix(disclosureRowPrefix) }
            .map(\.frame)
        return cellFrames.filter { cell in
            cell.width >= minimumTarget - tolerance && cell.height >= minimumTarget - tolerance
                && rows.contains { cell.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        }
    }

    /// Ukuran ≥ 44 × 44 pt untuk tombol, tautan, dan field teks konten app yang bisa diketuk; jarak ≥ 8 pt antar
    /// elemen yang tidak bertumpuk, tidak bersarang, dan tidak di dalam sel daftar. Elemen di bilah navigasi dan
    /// toolbar terdepan, keyboard, dan `systemElements` dikelola sistem dan hanya diaudit Apple.
    @discardableResult
    static func checkTouchTargets(_ app: XCUIApplication, context: String, requireTargets: Bool = false,
                                  excluding: (XCUIElement) -> Bool = { _ in false },
                                  file: StaticString = #filePath, line: UInt = #line) -> Int {
        let systemFrames = frontBarFrames(app) + app.keyboards.allElementsBoundByIndex.filter(\.exists).map(\.frame)
        let cellFrames = app.cells.allElementsBoundByIndex.filter(\.exists).map(\.frame)
        var targets: [(name: String, frame: CGRect, inCell: Bool)] = []
        // Bingkai baris FAQ, dihitung sekali dan hanya bila ada tombol tanpa nama yang perlu dicocokkan.
        var disclosureRows: [CGRect]?
        for query in [app.buttons, app.links, app.textFields] {
            for element in query.allElementsBoundByIndex where element.exists && element.isHittable && !excluding(element) {
                let frame = element.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let identifier = element.identifier
                let name = identifier.isEmpty ? element.label : identifier
                if systemFrames.contains(where: { $0.contains(center) }) { continue }
                if identifier.isEmpty && systemElements.contains(where: { $0.label == name }) { continue }
                if name.isEmpty {
                    let rows = disclosureRows ?? faqRowCells(app, cellFrames: cellFrames)
                    disclosureRows = rows
                    if rows.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(frame) }) {
                        print("AUDIT-SYSTEM | \(context) | penunjuk buka-tutup DisclosureGroup | \(describe(frame))")
                        continue
                    }
                }
                if frame.width < minimumTarget - tolerance || frame.height < minimumTarget - tolerance {
                    XCTFail("\(context): target sentuh \(name) berukuran \(Int(frame.width.rounded()))×\(Int(frame.height.rounded())) pt, kurang dari 44 pt",
                            file: file, line: line)
                }
                targets.append((name, frame, cellFrames.contains { $0.contains(center) }))
            }
        }
        if requireTargets && targets.isEmpty {
            XCTFail("\(context): tidak ada elemen konten yang bisa diketuk untuk diperiksa", file: file, line: line)
        }
        let free = targets.filter { !$0.inCell }
        for (index, a) in free.enumerated() {
            for b in free.dropFirst(index + 1) {
                if a.frame.contains(b.frame) || b.frame.contains(a.frame) { continue }  // bersarang
                if a.frame.intersects(b.frame) {
                    XCTFail("\(context): \(a.name) dan \(b.name) bertumpuk", file: file, line: line)
                    continue
                }
                let dx = max(0, max(a.frame.minX, b.frame.minX) - min(a.frame.maxX, b.frame.maxX))
                let dy = max(0, max(a.frame.minY, b.frame.minY) - min(a.frame.maxY, b.frame.maxY))
                let gap = (dx * dx + dy * dy).squareRoot()
                if gap < minimumSpacing - tolerance {
                    XCTFail("\(context): jarak \(a.name) dan \(b.name) \(String(format: "%.1f", gap)) pt, kurang dari 8 pt", file: file, line: line)
                }
            }
        }
        return targets.count
    }
}

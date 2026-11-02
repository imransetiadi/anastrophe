import XCTest

/// Varian peluncuran audit: ukuran teks AX5 dan bahasa Inggris (bawaan: ukuran sistem, bahasa ID).
struct AuditVariant: CustomStringConvertible {
    var largeText = false
    var english = false

    var description: String { [largeText ? "AX5" : nil, english ? "EN" : "ID"].compactMap(\.self).joined(separator: " ") }
}

/// Pengecualian audit per elemen (spesifikasi Tujuan 8): satu jenis audit, satu elemen yang dikenali persis
/// lewat identifier, dan alasan tertulis. Pengecualian per jenis audit tidak diizinkan.
struct AuditExemption {
    let type: XCUIAccessibilityAuditType
    let identifier: String
    let reason: String
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

/// Konteks satu halaman audit untuk kebijakan pengecualian.
private struct AuditPage {
    let context: String
    let scrolled: Bool
    /// Bingkai bilah navigasi/toolbar terdepan; hanya diisi untuk halaman tergulir.
    let barFrames: [CGRect]
    /// Judul dan tombol kembali buatan `UINavigationBar`.
    let systemBarElements: [BarElement]
}

/// Audit aksesibilitas satu keadaan layar: `performAccessibilityAudit` Apple ditambah cek ukuran dan jarak
/// target sentuh sendiri (TC-UX-01, TC-UX-02, TC-UX-04; ADR-0057).
@MainActor
enum AccessibilityAudit {
    /// Item bilah navigasi/toolbar app. Hanya `dynamicType`; kontras dan teks terpotong item ini tetap dihitung,
    /// kecuali lewat aturan bilah kaca di halaman tergulir.
    static let exemptions: [AuditExemption] = [
        AuditExemption(type: .dynamicType, identifier: "keys.add", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "keys.help", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "keys.lab", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "detail.lab_renew", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "help.done", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "add.back", reason: barItemReason),
        AuditExemption(type: .dynamicType, identifier: "add.close", reason: barItemReason),
    ]

    static let systemElements: [SystemElement] = [
        SystemElement(label: "Pengambil Lembar", reason: grabberReason),
        SystemElement(label: "Sheet Grabber", reason: grabberReason),
    ]

    static let barItemReason = "Item bilah navigasi/toolbar di iOS tidak mengikuti Dynamic Type; sebagai gantinya sistem "
        + "menampilkan Large Content Viewer saat item ditekan lama."
    static let grabberReason = "Grabber lembar dibuat sistem untuk lembar dengan beberapa detent; ukurannya (±73 × 24 pt) "
        + "tidak bisa diatur app. Tetap diaudit hitRegion Apple."
    static let disabledContrastReason = "WCAG 1.4.3: komponen UI yang nonaktif tidak wajib memenuhi kontras."
    static let underBarReason = "Halaman tergulir: elemen beririsan dengan bilah navigasi/toolbar dan dirender di bawah "
        + "bahan kaca (efek tepi gulir), sehingga piksel yang diukur bercampur dengan bilah dan konten lain."
    static let systemNavigationBarReason = "Judul dan tombol kembali dibuat UINavigationBar: ukuran, batas ukuran, dan "
        + "pemotongan teksnya diatur sistem, bukan tata letak app; app hanya memberi teks judul."

    /// Jenis audit yang hasilnya bergantung pada piksel/tata letak di bawah bahan kaca bilah sesudah digulir.
    static let glassAffectedTypes: [XCUIAccessibilityAuditType] = [.contrast, .textClipped, .dynamicType]
    /// Jenis audit yang dikecualikan untuk judul dan tombol kembali buatan sistem.
    static let systemBarTextTypes: [XCUIAccessibilityAuditType] = [.textClipped, .dynamicType]
    /// Identifier tombol kembali buatan `UINavigationBar`.
    static let backButtonIdentifier = "BackButton"

    static let minimumTarget: CGFloat = 44
    static let minimumSpacing: CGFloat = 8
    static let tolerance: CGFloat = 0.5
    static let maximumPreparationSwipes = 8

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
            guard let swipes = scrollUntilHittable(target, swiping: container) else {
                XCTFail("\(screen) \(variant): elemen persiapan \(preparation) tidak muncul", file: file, line: line)
                return nil
            }
            target.tap()
            // Halaman pertama sudah tergulir bila persiapan menggulir kontainer layar yang diaudit itu sendiri
            // (topik FAQ di Bantuan). Riwayat lengkap dibuka sebagai layar baru di posisi teratas.
            scrolled = swipes > 0 && screen.preparationContainer == screen.scrollContainer
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

    /// Jumlah gulir kontainer sampai elemen bisa diketuk, atau nil bila elemen tetap tidak bisa diketuk.
    private static func scrollUntilHittable(_ element: XCUIElement, swiping container: XCUIElement) -> Int? {
        // Baris daftar di luar layar belum ada di pohon aksesibilitas: tunggu layar dimuat, lalu gulir.
        _ = element.waitForExistence(timeout: 5)
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maximumPreparationSwipes {
            container.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable ? swipes : nil
    }

    // MARK: Audit

    /// Audit dan cek target sentuh di halaman pertama, lalu sesudah setiap gulir kontainer layar sampai `pages`
    /// habis atau gulir tidak lagi membawa ke posisi baru.
    static func auditPages(_ opened: OpenedScreen, screen: AuditScreen, context: String, pages: Int,
                           file: StaticString = #filePath, line: UInt = #line) {
        let app = opened.app
        let container = pages > 0 ? scrollContainer(of: screen, in: app, context: context, file: file, line: line) : nil
        // Posisi setiap halaman dicatat sebelum diaudit. Audit Apple sendiri bisa menggeser isi daftar (terlihat di
        // ujung konten pada AX5), jadi halaman baru harus berbeda dari semua posisi yang sudah diaudit, bukan hanya
        // dari posisi sesudah audit terakhir.
        var audited = container.map { [settledFingerprint($0)] } ?? []
        if let first = audited.first { print("AUDIT-POS | \(context) hlm 1 | \(first.summary)") }
        audit(app, context: "\(context) hlm 1", scrolled: opened.scrolled, file: file, line: line)
        var checked = checkTouchTargets(app, context: "\(context) hlm 1", file: file, line: line)
        if let container {
            for page in 2...(pages + 1) {
                guard let current = swipeToNewPosition(container, audited: audited) else { break }
                audited.append(current)
                print("AUDIT-POS | \(context) hlm \(page) | \(current.summary)")
                audit(app, context: "\(context) hlm \(page)", scrolled: true, file: file, line: line)
                checked += checkTouchTargets(app, context: "\(context) hlm \(page)", file: file, line: line)
            }
        }
        // Di AX5 halaman pertama bisa tanpa tombol; syaratnya berlaku untuk seluruh halaman yang diaudit.
        if screen.hasContentTargets && checked == 0 {
            XCTFail("\(context): tidak ada elemen konten yang bisa diketuk untuk diperiksa", file: file, line: line)
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
            texts = container.descendants(matching: .staticText).allElementsBoundByIndex.map { ($0.label, $0.frame) }
            visible = container.frame
        }
        let top = texts.filter { $0.frame.intersects(visible) }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .prefix(6)
        return ScrollFingerprint(texts: top.map { (label: $0.label, minY: $0.frame.minY) })
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
    private static func swipeToNewPosition(_ container: XCUIElement, audited: [ScrollFingerprint]) -> ScrollFingerprint? {
        for _ in 0..<2 {
            container.swipeUp()
            let current = settledFingerprint(container)
            if current.isNew(comparedTo: audited) { return current }
        }
        return nil
    }

    /// Sidik jari sesudah isi kontainer diam: gulir momentum atau pantulan di ujung konten bisa masih berjalan
    /// sesudah `swipeUp()` kembali.
    private static func settledFingerprint(_ container: XCUIElement) -> ScrollFingerprint {
        var last = fingerprint(container)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.3)
            let current = fingerprint(container)
            if let moved = current.distance(to: last), moved <= ScrollFingerprint.settledDistance { return current }
            last = current
        }
        return last
    }

    /// `scrolled`: halaman sesudah digulir, sehingga sebagian konten berada di bawah bahan kaca bilah sistem.
    static func audit(_ app: XCUIApplication, context: String, scrolled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        attachScreenshot(of: app, named: context)
        let page = AuditPage(context: context, scrolled: scrolled, barFrames: scrolled ? frontBarFrames(app) : [],
                             systemBarElements: systemNavigationBarElements(app))
        // Baris halaman dan isu dihitung untuk bukti QA (jumlah halaman, temuan per jenis dan per keadaan).
        print("AUDIT-PAGE | \(context) | scrolled=\(scrolled) | bars=\(page.barFrames.map { describe($0) })")
        do {
            try performAudit(app, page: page)
        } catch {
            XCTFail("\(context): audit tidak bisa dijalankan: \(error)", file: file, line: line)
        }
    }

    /// Audit Apple kadang berhenti dengan "Audit failed to complete in time" (kode -56) pada daftar panjang di AX5.
    /// Itu kegagalan infrastruktur, bukan temuan: audit diulang sekali, lalu gagal bila tetap tidak selesai.
    private static func performAudit(_ app: XCUIApplication, page: AuditPage) throws {
        do {
            try app.performAccessibilityAudit(for: .all) { evaluate($0, on: page) }
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            print("AUDIT-RETRY | \(page.context) | \(error.localizedDescription)")
            try app.performAccessibilityAudit(for: .all) { evaluate($0, on: page) }
        }
    }

    /// Kebijakan pengecualian (spesifikasi Tujuan 8, ADR-0057). true = isu tidak menggagalkan test; setiap isu
    /// dicetak dengan awalan sesuai keputusannya.
    private static func evaluate(_ issue: XCUIAccessibilityAuditIssue, on page: AuditPage) -> Bool {
        let type = name(of: issue.auditType)
        let detail = issue.detailedDescription.replacingOccurrences(of: "\n", with: " ")
        guard let element = issue.element, element.exists else {
            // Isu tanpa elemen tidak bisa dicek letaknya terhadap bilah. Di halaman tergulir, isu dari jenis yang
            // terpengaruh bahan kaca hanya dicetak untuk dihitung; di halaman yang belum digulir semuanya gagal.
            if page.scrolled && glassAffectedTypes.contains(issue.auditType) {
                print("AUDIT-SKIP | \(page.context) | \(type) | \(issue.compactDescription) | \(detail)")
                return true
            }
            print("AUDIT-ISSUE | \(page.context) | \(type) | \(issue.compactDescription) | - | \(detail)")
            return false
        }
        if let reason = exemptionReason(for: issue, element: element, on: page) {
            print("AUDIT-EXEMPT | \(page.context) | \(type) | \(issue.compactDescription) | \(describe(element)) | \(reason)")
            return true
        }
        print("AUDIT-ISSUE | \(page.context) | \(type) | \(issue.compactDescription) | \(describe(element)) | \(detail)")
        return false
    }

    /// Alasan pengecualian isu yang punya elemen, atau nil bila isu dihitung.
    private static func exemptionReason(for issue: XCUIAccessibilityAuditIssue, element: XCUIElement, on page: AuditPage) -> String? {
        let type = issue.auditType
        if type == .contrast && !element.isEnabled { return disabledContrastReason }
        if page.scrolled && glassAffectedTypes.contains(type) {
            let frame = element.frame
            if page.barFrames.contains(where: { $0.intersects(frame) }) { return underBarReason }
        }
        let identifier = element.identifier
        if !identifier.isEmpty, let exemption = exemptions.first(where: { $0.type == type && $0.identifier == identifier }) {
            return exemption.reason
        }
        if systemBarTextTypes.contains(type) && isSystemNavigationBarElement(element, in: page.systemBarElements) {
            return systemNavigationBarReason
        }
        return nil
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
        for query in [app.buttons, app.links, app.textFields] {
            for element in query.allElementsBoundByIndex where element.exists && element.isHittable && !excluding(element) {
                let frame = element.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let identifier = element.identifier
                let name = identifier.isEmpty ? element.label : identifier
                if systemFrames.contains(where: { $0.contains(center) }) { continue }
                if identifier.isEmpty && systemElements.contains(where: { $0.label == name }) { continue }
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

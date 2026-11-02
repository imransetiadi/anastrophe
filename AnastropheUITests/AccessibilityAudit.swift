import XCTest

/// Varian peluncuran audit: ukuran teks AX5 dan bahasa Inggris (bawaan: ukuran sistem, bahasa ID).
struct AuditVariant: CustomStringConvertible {
    var largeText = false
    var english = false

    var description: String { [largeText ? "AX5" : nil, english ? "EN" : "ID"].compactMap(\.self).joined(separator: " ") }
}

/// Pengecualian audit per elemen (spesifikasi Tujuan 8): satu jenis audit, satu elemen yang dikenali persis
/// (identifier atau label), dan alasan tertulis. Pengecualian per jenis audit tidak diizinkan.
struct AuditExemption {
    let type: XCUIAccessibilityAuditType
    let element: String
    let reason: String
}

/// Audit aksesibilitas satu keadaan layar: `performAccessibilityAudit` Apple ditambah cek ukuran dan jarak
/// target sentuh sendiri (TC-UX-01, TC-UX-02, TC-UX-04; ADR-0057).
@MainActor
enum AccessibilityAudit {
    static let exemptions: [AuditExemption] = []

    /// Elemen milik sistem (mis. grabber lembar) yang dikecualikan dari cek target sentuh buatan sendiri.
    /// Elemen ini tetap diaudit `hitRegion` Apple.
    static let systemElements: Set<String> = []

    static let minimumTarget: CGFloat = 44
    static let minimumSpacing: CGFloat = 8
    static let tolerance: CGFloat = 0.5

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
    static func open(_ screen: AuditScreen, variant: AuditVariant, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication? {
        let app = launch(screen, variant: variant)
        if let preparation = screen.preparation {
            let element = element(preparation, in: app)
            guard scrollUntilHittable(element, in: app) else {
                XCTFail("\(screen) \(variant): elemen persiapan \(preparation) tidak muncul", file: file, line: line)
                return nil
            }
            element.tap()
        }
        guard element(screen.marker, in: app).waitForExistence(timeout: 10) else {
            XCTFail("\(screen) \(variant): penanda \(screen.marker) tidak muncul", file: file, line: line)
            return nil
        }
        return app
    }

    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private static func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        // Baris daftar di luar layar belum ada di pohon aksesibilitas: tunggu layar dimuat, lalu gulir.
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: Audit

    /// Audit dan cek target sentuh di halaman pertama, lalu sesudah setiap gulir sampai `pages` habis atau konten
    /// tidak bergerak lagi.
    static func auditPages(_ app: XCUIApplication, screen: AuditScreen, context: String, pages: Int,
                           file: StaticString = #filePath, line: UInt = #line) {
        audit(app, context: "\(context) hlm 1", scrolled: false, file: file, line: line)
        var checked = checkTouchTargets(app, context: "\(context) hlm 1", file: file, line: line)
        if pages > 0 {
            for page in 2...(pages + 1) {
                let before = fingerprint(app)
                app.swipeUp()
                guard fingerprint(app) != before else { break }
                audit(app, context: "\(context) hlm \(page)", scrolled: true, file: file, line: line)
                checked += checkTouchTargets(app, context: "\(context) hlm \(page)", file: file, line: line)
            }
        }
        // Di AX5 halaman pertama bisa tanpa tombol; syaratnya berlaku untuk seluruh halaman yang diaudit.
        if screen.hasContentTargets && checked == 0 {
            XCTFail("\(context): tidak ada elemen konten yang bisa diketuk untuk diperiksa", file: file, line: line)
        }
    }

    /// Posisi beberapa teks pertama; tidak berubah bila gulir sudah sampai ujung.
    private static func fingerprint(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.prefix(6).map { "\($0.label)@\(Int($0.frame.minY))" }
    }

    /// `scrolled`: halaman sesudah digulir, sehingga sebagian konten berada di bawah bahan kaca bilah sistem.
    static func audit(_ app: XCUIApplication, context: String, scrolled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        attachScreenshot(of: app, named: context)
        let barFrames = scrolled ? systemBarFrames(app) : []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                if isExempt(issue, underBars: barFrames) { return true }
                // Baris ini dihitung untuk bukti QA (jumlah temuan per jenis dan per keadaan).
                let detail = issue.detailedDescription.replacingOccurrences(of: "\n", with: " ")
                print("AUDIT-ISSUE | \(context) | \(name(of: issue.auditType)) | \(issue.compactDescription) | \(describe(issue.element)) | \(detail)")
                return false
            }
        } catch {
            XCTFail("\(context): audit tidak bisa dijalankan: \(error)", file: file, line: line)
        }
    }

    static func isExempt(_ issue: XCUIAccessibilityAuditIssue, underBars barFrames: [CGRect] = []) -> Bool {
        guard let element = issue.element, element.exists else { return false }
        if issue.auditType == .contrast {
            // WCAG 1.4.3: komponen UI yang nonaktif tidak wajib memenuhi kontras.
            if !element.isEnabled { return true }
            // Sesudah digulir, elemen yang beririsan dengan bilah navigasi/toolbar dirender di atas bahan kaca
            // dengan konten lain di belakangnya. Elemen yang sama diaudit tanpa halangan di halaman pertama atau
            // halaman sebelumnya.
            if barFrames.contains(where: { $0.intersects(element.frame) }) { return true }
        }
        return exemptions.contains { $0.type == issue.auditType && ($0.element == element.identifier || $0.element == element.label) }
    }

    private static func systemBarFrames(_ app: XCUIApplication) -> [CGRect] {
        (app.navigationBars.allElementsBoundByIndex + app.toolbars.allElementsBoundByIndex).filter(\.exists).map(\.frame)
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

    private static func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Screenshot \(name)") { $0.add(attachment) }
    }

    // MARK: Target sentuh

    /// Ukuran ≥ 44 × 44 pt untuk tombol, tautan, dan field teks konten app yang bisa diketuk; jarak ≥ 8 pt antar
    /// elemen yang tidak bertumpuk, tidak bersarang, dan tidak di dalam sel daftar. Elemen di bilah navigasi,
    /// toolbar, dan keyboard dikelola sistem dan hanya diaudit Apple.
    @discardableResult
    static func checkTouchTargets(_ app: XCUIApplication, context: String, requireTargets: Bool = false,
                                  excluding: (XCUIElement) -> Bool = { _ in false },
                                  file: StaticString = #filePath, line: UInt = #line) -> Int {
        let systemFrames = (app.navigationBars.allElementsBoundByIndex + app.toolbars.allElementsBoundByIndex + app.keyboards.allElementsBoundByIndex)
            .filter(\.exists).map(\.frame)
        let cellFrames = app.cells.allElementsBoundByIndex.filter(\.exists).map(\.frame)
        var targets: [(name: String, frame: CGRect, inCell: Bool)] = []
        for query in [app.buttons, app.links, app.textFields] {
            for element in query.allElementsBoundByIndex where element.exists && element.isHittable && !excluding(element) {
                let frame = element.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let name = element.identifier.isEmpty ? element.label : element.identifier
                if systemFrames.contains(where: { $0.contains(center) }) || systemElements.contains(name) { continue }
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

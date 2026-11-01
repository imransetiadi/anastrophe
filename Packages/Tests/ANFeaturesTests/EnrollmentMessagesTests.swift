import ANCore
import Foundation
import Testing
@testable import ANFeatures

@Suite("Teks alasan enrolment (FR-13, SDD §15)")
struct EnrollmentMessagesTests {
    @Test func setiapAlasanPunyaTeksSendiri() {
        let errors: [ANError] = [.enrollmentRejected(.notRegistered), .enrollmentRejected(.siteUnsupported),
                                 .enrollmentRejected(.duplicate), .enrollmentRejected(.pendingApproval), .cardLimitReached]
        let texts = errors.compactMap { EnrollmentMessages.text(for: $0) }
        #expect(texts.count == errors.count)
        #expect(Set(texts).count == errors.count)
        #expect(texts.allSatisfy { !$0.isEmpty && !$0.contains("NFC") })
    }

    @Test func galatLainTanpaTeksKhusus() {
        #expect(EnrollmentMessages.text(for: ANError.internalError) == nil)
        #expect(EnrollmentMessages.text(for: URLError(.timedOut)) == nil)
    }
}

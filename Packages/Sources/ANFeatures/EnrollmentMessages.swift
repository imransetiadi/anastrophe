import ANCore

/// Teks alasan enrolment ditolak (FR-13, SDD §15) dalam ID dan EN; nil untuk galat lain.
enum EnrollmentMessages {
    static func text(for error: any Error) -> String? {
        guard let error = error as? ANError else { return nil }
        switch error {
        case .enrollmentRejected(.notRegistered): return localized("enroll.error.not_registered")
        case .enrollmentRejected(.siteUnsupported): return localized("enroll.error.site_unsupported")
        case .enrollmentRejected(.duplicate): return localized("enroll.error.duplicate")
        case .enrollmentRejected(.pendingApproval): return localized("enroll.error.pending_approval")
        case .enrollmentRejected(.invitationInvalid): return localized("enroll.error.invitation_invalid")
        case .cardLimitReached: return localized("enroll.error.limit")
        default: return nil
        }
    }
}

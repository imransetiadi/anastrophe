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
        case .enrollmentRejected(.siteCodeUnknown): return localized("add.error.site_code_unknown")
        case .enrollmentRejected(.pendingLimit): return localized("enroll.error.pending_limit")
        case .cardUnreadable: return localized("add.error.unreadable")
        case .cardReaderUnavailable: return localized("add.error.reader_unavailable")
        case .serviceUnavailable: return localized("add.error.service_unavailable")
        case .siteChannelUnavailable: return localized("add.error.site_channel_unavailable")
        case .siteChannelsNotOffered: return localized("add.error.site_channels_not_offered")
        case .channelUnavailable: return localized("add.error.channel_unavailable")
        default: return nil
        }
    }
}

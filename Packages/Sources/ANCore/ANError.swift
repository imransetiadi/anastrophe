/// Error domain lintas modul. Kode katalog mengikuti SDD §15.
public enum ANError: Error, Equatable, Sendable {
    case cardLimitReached
    case channelUnavailable(ChannelAvailability)
    case keyUnavailable
    case invalidData
    case internalError
    /// Server menolak enrolment kartu (FR-13, ADR-0032).
    case enrollmentRejected(EnrollmentRejection)
}

/// Alasan enrolment kartu ditolak server (SDD §15).
public enum EnrollmentRejection: String, Equatable, Sendable {
    case notRegistered, siteUnsupported, duplicate, pendingApproval, invitationInvalid
}

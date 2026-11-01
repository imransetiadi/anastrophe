/// Error domain lintas modul. Kode katalog mengikuti SDD §15.
public enum ANError: Error, Equatable, Sendable {
    case cardLimitReached
    case channelUnavailable(ChannelAvailability)
    case keyUnavailable
    case invalidData
    case internalError
    /// Server menolak enrolment kartu (FR-13, ADR-0032).
    case enrollmentRejected(EnrollmentRejection)
    /// Kartu fisik tidak terbaca: batas waktu, jenis kartu tidak didukung, atau identitas tidak sah
    /// (`ENR-UNREADABLE`, FR-13).
    case cardUnreadable
    /// Perangkat ini tidak bisa membaca kartu fisik (mis. simulator atau model lama).
    case cardReaderUnavailable
    /// Build tanpa alamat layanan (`ANAPIBaseURL` kosong), jadi enrolment belum tersedia.
    case serviceUnavailable
    /// Kanal yang diizinkan kebijakan gedung tidak ada yang bisa dipakai di iPhone ini (ADR-0049).
    case siteChannelUnavailable
}

/// Alasan enrolment kartu ditolak server (SDD §15).
public enum EnrollmentRejection: String, Equatable, Sendable {
    case notRegistered, siteUnsupported, duplicate, pendingApproval, invitationInvalid
    /// Kode gedung tak dikenal atau tidak berbentuk sah (`SITE-NOT-FOUND`, ADR-0044).
    case siteCodeUnknown
    /// Kartu sudah punya batas permintaan perangkat tambahan yang menunggu operator (`ENR-PENDING-LIMIT`,
    /// ADR-0047).
    case pendingLimit
}

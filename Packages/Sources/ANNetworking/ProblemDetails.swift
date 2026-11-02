import ANCore
import Foundation

/// Error API dalam format RFC 9457. `type` berisi kode katalog SDD §15 (mis. `ENR-LIMIT`).
public struct ProblemDetails: Decodable, Error, Equatable, Sendable {
    public let type: String
    public let title: String?
    public let status: Int

    public init(type: String, title: String?, status: Int) {
        self.type = type
        self.title = title
        self.status = status
    }

    /// Kode yang punya padanan error domain; selebihnya diteruskan apa adanya.
    var domainError: (any Error)? {
        switch type {
        case "ENR-LIMIT": ANError.cardLimitReached
        case "ENR-NOT-REGISTERED": ANError.enrollmentRejected(.notRegistered)
        case "ENR-SITE-UNSUPPORTED": ANError.enrollmentRejected(.siteUnsupported)
        case "ENR-DUPLICATE": ANError.enrollmentRejected(.duplicate)
        case "ENR-PENDING-APPROVAL": ANError.enrollmentRejected(.pendingApproval)
        case "ENR-INVITATION-INVALID": ANError.enrollmentRejected(.invitationInvalid)
        case "SITE-NOT-FOUND": ANError.enrollmentRejected(.siteCodeUnknown)
        case "ENR-PENDING-LIMIT": ANError.enrollmentRejected(.pendingLimit)
        default: nil
        }
    }
}

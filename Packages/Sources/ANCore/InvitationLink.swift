import Foundation

/// Tautan undangan enrolment `https://<host>/i/<token>` (FR-12, ADR-0033). Token adalah 32 byte acak
/// dalam base64url tanpa padding (43 karakter). Berlaku atau tidaknya hanya diputuskan server.
public enum InvitationLink {
    static let tokenLength = 43
    private static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// Token dari tautan undangan; nil bila bukan https dengan host, path bukan `/i/<token>`, atau
    /// token tidak berbentuk sah.
    public static func token(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
        let components = url.pathComponents
        guard components.count == 3, components[0] == "/", components[1] == "i", isValidToken(components[2]) else { return nil }
        return components[2]
    }

    /// Tepat 43 karakter alfabet base64url (`A–Z`, `a–z`, `0–9`, `-`, `_`).
    public static func isValidToken(_ token: String) -> Bool {
        token.count == tokenLength && token.allSatisfy(alphabet.contains)
    }
}

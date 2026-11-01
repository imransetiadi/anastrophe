import Foundation
import LocalAuthentication

/// Hasil autentikasi pengguna. `LAContext` yang sama diteruskan ke operasi tanda
/// tangan Secure Enclave agar pengguna tidak diminta dua kali (SDD §6.1).
public struct AuthorizedContext: @unchecked Sendable {
    public let laContext: LAContext

    public init(laContext: LAContext) {
        self.laContext = laContext
    }
}

/// Autentikasi pengguna (Face ID/Touch ID/passcode), di balik protokol agar bisa di-mock.
public protocol UserAuthenticator: Sendable {
    func authenticate(reason: String) async throws -> AuthorizedContext
}

public struct LAUserAuthenticator: UserAuthenticator {
    public init() {}

    public func authenticate(reason: String) async throws -> AuthorizedContext {
        let context = LAContext()
        _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        return AuthorizedContext(laContext: context)
    }
}

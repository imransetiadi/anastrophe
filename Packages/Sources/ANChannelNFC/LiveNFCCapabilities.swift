#if os(iOS)
import CoreNFC
import SecureElementCredential

/// Implementasi live di atas CoreNFC dan SecureElementCredential.
public struct LiveNFCCapabilities: NFCCapabilities {
    public init() {}

    public var readingAvailable: Bool { NFCReaderSession.readingAvailable }
    public var cardSessionSupported: Bool { CardSession.isSupported }

    public func isCardSessionEligible() async -> Bool {
        await CardSession.isEligible
    }

    public func isCredentialSessionEligible() async -> Bool {
        // `isEligible` bisa melempar error; perlakukan sebagai tidak eligible.
        (try? await CredentialSession.isEligible) ?? false
    }
}
#endif

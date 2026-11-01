import ANCrypto
import CryptoKit
import LocalAuthentication
import Foundation

/// Signer perangkat lunak (pengganti Secure Enclave di test).
public struct SoftwareSigner: CredentialSigner {
    public let key: P256.Signing.PrivateKey

    public init(key: P256.Signing.PrivateKey) {
        self.key = key
    }

    public func sign(_ message: Data) throws -> Data {
        try key.signature(for: message).rawRepresentation
    }
}

/// Counter in-memory yang mencatat jumlah panggilan.
public final class InMemoryCounterStore: CounterStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data: UInt32] = [:]
    public private(set) var calls = 0

    public init() {}

    public func next(for credentialID: Data) throws -> UInt32 {
        lock.withLock {
            calls += 1
            let value = (values[credentialID] ?? 0) + 1
            values[credentialID] = value
            return value
        }
    }
}

/// Kredensial ANP/1 lengkap untuk test kanal: kunci group, kunci kredensial, counter.
public struct ANP1TestCredential: Sendable {
    public let groupKey = P256.Signing.PrivateKey()
    public let groupID = Data(repeating: 0xA1, count: 8)
    public let credentialKey = P256.Signing.PrivateKey()
    public let counters = InMemoryCounterStore()
    public let notAfter: Date
    public let suspended: Bool

    public init(notAfter: Date = .now.addingTimeInterval(7 * 86_400), suspended: Bool = false) {
        self.notAfter = notAfter
        self.suspended = suspended
    }

    public func material() -> CredentialMaterial {
        CredentialMaterial(
            credentialID: Data(repeating: 0xC1, count: 16),
            certificate: Data(repeating: 0xCE, count: 150),
            notAfter: notAfter,
            suspended: suspended,
            groupKeys: [groupID: [groupKey.publicKey]]
        )
    }

    public func provider() -> ANP1PhoneSession {
        ANP1PhoneSession(material: material(), signer: SoftwareSigner(key: credentialKey), counters: counters)
    }

    public func reader() -> SoftwareReader {
        SoftwareReader(groupKey: groupKey, groupID: groupID)
    }
}

/// Autentikasi palsu: sukses atau dibatalkan pengguna.
public struct FakeAuthenticator: UserAuthenticator {
    public struct Cancelled: Error {}
    public let succeeds: Bool
    /// Bila diisi, autentikasi menunggu sampai gate dibuka (meniru prompt Face ID).
    public let gate: AsyncGate?

    public init(succeeds: Bool = true, gate: AsyncGate? = nil) {
        self.succeeds = succeeds
        self.gate = gate
    }

    public func authenticate(reason: String) async throws -> AuthorizedContext {
        await gate?.wait()
        guard succeeds else { throw Cancelled() }
        return AuthorizedContext(laContext: LAContext())
    }
}

/// Nilai bersama yang aman diakses dari banyak task (pengganti `Mutex` di closure escaping).
public final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    public init(_ value: Value) {
        stored = value
    }

    public var value: Value { lock.withLock { stored } }

    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        try lock.withLock { try body(&stored) }
    }
}

/// Sinyal sekali pakai untuk menahan sebuah langkah async sampai test mengizinkan.
public final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if opened { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    public func open() {
        let pending = lock.withLock {
            opened = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

import ANCore

/// Pembaca dengan hasil tetap: untuk test, dan untuk e2e di simulator lewat `-ANLabCardReader` (DEBUG),
/// karena simulator tidak bisa membaca kartu fisik.
public struct FixedCardOwnershipReader: CardOwnershipReader {
    public enum Outcome: Sendable {
        case identity(CardIdentity)
        case failure(ANError)
        case cancelled
    }

    private let outcome: Outcome

    public init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public func readIdentity() async throws -> CardIdentity {
        switch outcome {
        case .identity(let identity): identity
        case .failure(let error): throw error
        case .cancelled: throw CancellationError()
        }
    }
}

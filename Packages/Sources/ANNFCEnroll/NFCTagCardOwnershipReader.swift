#if os(iOS) && canImport(CoreNFC)
import ANCore
@preconcurrency import CoreNFC
import Foundation

/// Pembaca kartu fisik live (FR-11) di atas `NFCTagReaderSession`. Hanya `identifier` yang dibaca
/// (ADR-0001, CLAUDE.md aturan 1); identitas tidak pernah dicatat (aturan 6). Butuh iPhone dan kartu
/// (uji H); di simulator `readingAvailable` bernilai false sehingga dilempar `cardReaderUnavailable`.
public final class NFCTagCardOwnershipReader: NSObject, CardOwnershipReader, @unchecked Sendable {
    private let prompt: String
    private let multipleCardsMessage: String
    private let queue = DispatchQueue(label: "app.anastrophe.card-reader")
    private let lock = NSLock()
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<CardIdentity, any Error>?

    /// `prompt` tampil di lembar sistem saat menunggu kartu; `multipleCardsMessage` bila lebih dari satu
    /// kartu terdeteksi. Keduanya teks terlokalisasi tanpa istilah teknis.
    public init(prompt: String, multipleCardsMessage: String) {
        self.prompt = prompt
        self.multipleCardsMessage = multipleCardsMessage
    }

    public func readIdentity() async throws -> CardIdentity {
        guard NFCReaderSession.readingAvailable else { throw ANError.cardReaderUnavailable }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CardIdentity, any Error>) in
                lock.lock()
                defer { lock.unlock() }
                guard self.continuation == nil,
                      let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: queue)
                else {
                    continuation.resume(throwing: ANError.cardReaderUnavailable)
                    return
                }
                self.continuation = continuation
                self.session = session
                session.alertMessage = prompt
                session.begin()
            }
        } onCancel: {
            lock.withLock { session }?.invalidate()
        }
    }

    /// Menyelesaikan pembacaan milik `session` sekali. Panggilan berikutnya (mis. invalidasi setelah sukses)
    /// dan callback dari sesi lama diabaikan, sehingga tidak menyelesaikan pembacaan yang lebih baru.
    private func finish(_ result: Result<CardIdentity, any Error>, session: NFCTagReaderSession) {
        let continuation = lock.withLock { () -> CheckedContinuation<CardIdentity, any Error>? in
            guard self.session === session else { return nil }
            defer {
                self.continuation = nil
                self.session = nil
            }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    static func detected(_ tag: NFCTag) -> DetectedTag {
        switch tag {
        case .miFare(let tag): .miFare(identifier: tag.identifier)
        case .iso7816(let tag): .iso7816(identifier: tag.identifier, typeA: tag.historicalBytes != nil)
        case .iso15693(let tag): .iso15693(identifier: tag.identifier)
        case .feliCa: .unsupported
        @unknown default: .unsupported
        }
    }
}

extension NFCTagCardOwnershipReader: NFCTagReaderSessionDelegate {
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        if (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(CancellationError()), session: session)
        } else {
            finish(.failure(ANError.cardUnreadable), session: session)  // batas waktu sistem dan galat sesi lain
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = multipleCardsMessage
            session.restartPolling()
            return
        }
        nonisolated(unsafe) let session = session
        nonisolated(unsafe) let connected = tag
        session.connect(to: connected) { [weak self] error in
            guard let self else { return }
            // Identifier dibaca setelah connect berhasil; sebelum connect nilainya bisa kosong (review akhir #3).
            guard error == nil, let identity = CardIdentityMapper.identity(for: Self.detected(connected)) else {
                finish(.failure(ANError.cardUnreadable), session: session)
                session.invalidate()
                return
            }
            finish(.success(identity), session: session)
            session.invalidate()
        }
    }
}
#endif

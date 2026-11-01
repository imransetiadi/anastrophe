import ANCore
import Foundation

/// Transport HTTP di balik protokol agar bisa di-mock. Topologi backend
/// (ADR-0014) belum diputuskan, jadi base URL datang dari konfigurasi build.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ANError.internalError }
        return (data, http)
    }
}

/// Klien REST `/v1` (SDD §8.5). **Kontrak masih draf** hingga rencana backend
/// (ADR-0014). Pinning dan App Attest menyusul di rencana itu.
public struct APIClient: Sendable {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public let baseURL: URL
    private let transport: any HTTPTransport

    public init(baseURL: URL, transport: any HTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// `GET /v1/config` → kanal yang diizinkan untuk wilayah/akun ini (FR-04).
    public func fetchConfig() async throws -> RemoteConfig {
        let data = try await perform(URLRequest(url: baseURL.appending(path: "v1/config")))
        return try Self.decoder.decode(RemoteConfig.self, from: data)
    }

    /// `POST /v1/enrollments`: enrolment untuk kartu fisik terdaftar (ADR-0031). Identitas kartu hanya
    /// lewat TLS; server menghitung HMAC per gedung. Security code dan App Attest menyusul (SDD §8.4.1).
    public func createEnrollment(deviceID: String, siteID: String, card: CardIdentity, idempotencyKey: UUID) async throws -> EnrollmentStart {
        struct Body: Encodable {
            struct Card: Encodable {
                let tech: String
                let id: String
            }
            let deviceID: String
            let siteID: String
            let card: Card
            enum CodingKeys: String, CodingKey { case deviceID = "device_id", siteID = "site_id", card }
        }
        return try await postEnrollment(Body(deviceID: deviceID, siteID: siteID, card: .init(tech: card.technology.rawValue, id: card.hex)), idempotencyKey: idempotencyKey)
    }

    /// `POST /v1/enrollments` dengan undangan (FR-12, ADR-0033): token menggantikan kartu fisik. Gedung
    /// dan zona berasal dari undangan, jadi body hanya perangkat dan token.
    public func createEnrollment(deviceID: String, invitation: String, idempotencyKey: UUID) async throws -> EnrollmentStart {
        try await postEnrollment(["device_id": deviceID, "invitation": invitation], idempotencyKey: idempotencyKey)
    }

    private func postEnrollment(_ body: some Encodable, idempotencyKey: UUID) async throws -> EnrollmentStart {
        var request = URLRequest(url: baseURL.appending(path: "v1/enrollments"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(body)
        return try Self.decoder.decode(EnrollmentStart.self, from: try await perform(request))
    }

    /// `POST /v1/enrollments/{id}/credentials`: kirim kunci publik kanal, terima sertifikat (FR-16).
    public func submitCredentialKey(enrollmentID: String, channel: ChannelKind, publicKey: Data, statusTokenHash: Data? = nil, idempotencyKey: UUID) async throws -> ProvisionedCredential {
        var request = URLRequest(url: baseURL.appending(path: "v1/enrollments/\(enrollmentID)/credentials"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        var body = ["channel": channel.rawValue, "public_key": publicKey.base64EncodedString()]
        // ADR-0037: hanya hash token baca status yang dikirim; tokennya tetap di perangkat.
        body["status_token_hash"] = statusTokenHash?.base64EncodedString()
        request.httpBody = try JSONEncoder().encode(body)
        return try ProvisionedCredential.decode(try await perform(request))
    }

    /// `POST /v1/credentials/{cred}:challenge` → nonce perpanjangan (FR-45).
    public func renewalChallenge(credentialID: Data) async throws -> RenewalChallenge {
        var request = URLRequest(url: credentialURL(credentialID, action: "challenge"))
        request.httpMethod = "POST"
        return try Self.decoder.decode(RenewalChallenge.self, from: try await perform(request))
    }

    /// `POST /v1/credentials/{cred}:renew`: tanda tangan atas nonce → sertifikat baru (FR-45).
    public func renewCredential(credentialID: Data, nonce: Data, signature: Data, statusTokenHash: Data? = nil, idempotencyKey: UUID) async throws -> ProvisionedCredential {
        var request = URLRequest(url: credentialURL(credentialID, action: "renew"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        var body = ["nonce": nonce.base64EncodedString(), "signature": signature.base64EncodedString()]
        body["status_token_hash"] = statusTokenHash?.base64EncodedString()  // kartu lama tanpa token (ADR-0037)
        request.httpBody = try JSONEncoder().encode(body)
        return try ProvisionedCredential.decode(try await perform(request))
    }

    /// `DELETE /v1/cards/{id}`: hapus kartu dengan bukti kepemilikan kunci (FR-31, ADR-0026).
    public func deleteCard(cardID: String, credentialID: Data, nonce: Data, signature: Data, idempotencyKey: UUID) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/cards/\(cardID)"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode([
            "credential_id": credentialID.base64EncodedString(), "nonce": nonce.base64EncodedString(), "signature": signature.base64EncodedString(),
        ])
        _ = try await perform(request)
    }

    /// `GET /v1/cards/{id}/status` dengan token baca status sebagai bearer (ADR-0037). Tanpa tanda tangan
    /// kunci kredensial, jadi tidak ada prompt autentikasi.
    public func cardStatus(cardID: String, token: Data) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/cards/\(cardID)/status"))
        let encoded = token.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        request.setValue("Bearer \(encoded)", forHTTPHeaderField: "Authorization")
        struct Reply: Decodable { let status: String }
        return try Self.decoder.decode(Reply.self, from: try await perform(request)).status
    }

    /// `cred_id` dalam hex huruf kecil, diikuti `:aksi` (SDD §8.5).
    private func credentialURL(_ credentialID: Data, action: String) -> URL {
        baseURL.appending(path: "v1/credentials/\(credentialID.hexString):\(action)")
    }

    /// Respons 2xx → body; RFC 9457 → error domain atau `ProblemDetails`.
    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard contentType.hasPrefix("application/problem+json"),
                  let problem = try? Self.decoder.decode(ProblemDetails.self, from: data)
            else { throw ANError.internalError }
            throw problem.domainError ?? problem
        }
        return data
    }
}

/// Hasil `POST /v1/enrollments`: perangkat pertama diprovisikan, perangkat tambahan menunggu
/// persetujuan operator sampai ada akun (ADR-0032).
public struct EnrollmentStart: Equatable, Sendable, Decodable {
    public enum Status: String, Equatable, Sendable, Decodable {
        case provisioning = "PROVISIONING"
        case pendingApproval = "PENDING_APPROVAL"
    }

    public let enrollmentID: String
    public let status: Status

    public init(enrollmentID: String, status: Status) {
        self.enrollmentID = enrollmentID
        self.status = status
    }

    enum CodingKeys: String, CodingKey { case enrollmentID = "enrollment_id", status }
}

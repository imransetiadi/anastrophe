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

    /// `POST /v1/enrollments` versi tracer backend R1: mendaftarkan kartu untuk perangkat di gedung.
    /// Enrolment produksi memakai identitas kartu fisik, security code, dan App Attest (SDD §8.4.1).
    public func createEnrollment(deviceID: String, siteID: String, idempotencyKey: UUID) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/enrollments"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(["device_id": deviceID, "site_id": siteID])
        struct Created: Decodable {
            let enrollmentID: String
            enum CodingKeys: String, CodingKey { case enrollmentID = "enrollment_id" }
        }
        return try Self.decoder.decode(Created.self, from: try await perform(request)).enrollmentID
    }

    /// `POST /v1/enrollments/{id}/credentials`: kirim kunci publik kanal, terima sertifikat (FR-16).
    public func submitCredentialKey(enrollmentID: String, channel: ChannelKind, publicKey: Data, idempotencyKey: UUID) async throws -> ProvisionedCredential {
        var request = URLRequest(url: baseURL.appending(path: "v1/enrollments/\(enrollmentID)/credentials"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(["channel": channel.rawValue, "public_key": publicKey.base64EncodedString()])
        return try ProvisionedCredential.decode(try await perform(request))
    }

    /// `POST /v1/credentials/{cred}:challenge` → nonce perpanjangan (FR-45).
    public func renewalChallenge(credentialID: Data) async throws -> RenewalChallenge {
        var request = URLRequest(url: credentialURL(credentialID, action: "challenge"))
        request.httpMethod = "POST"
        return try Self.decoder.decode(RenewalChallenge.self, from: try await perform(request))
    }

    /// `POST /v1/credentials/{cred}:renew`: tanda tangan atas nonce → sertifikat baru (FR-45).
    public func renewCredential(credentialID: Data, nonce: Data, signature: Data, idempotencyKey: UUID) async throws -> ProvisionedCredential {
        var request = URLRequest(url: credentialURL(credentialID, action: "renew"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(["nonce": nonce.base64EncodedString(), "signature": signature.base64EncodedString()])
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

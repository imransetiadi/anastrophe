import ANCore
import Foundation
import Testing
@testable import ANNetworking

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    let status: Int
    let body: Data
    let contentType: String

    init(status: Int = 200, body: String, contentType: String = "application/json") {
        self.status = status
        self.body = Data(body.utf8)
        self.contentType = contentType
    }

    var lastRequest: URLRequest? { lock.withLock { requests.last } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
        return (body, response)
    }
}

let provisionedJSON = """
{
  "credential_id": "wcHBwcHBwcHBwcHBwcHBwQ==",
  "channel": "ble",
  "certificate": "zs7Ozs4=",
  "not_after": "2026-11-08T00:00:00Z",
  "site_name": "Menara A",
  "zones": ["Lobi", "Lift"],
  "group_keys": {"a1a2a3a4a5a6a7a8": ["BAE=", "BAI="]}
}
"""

@Suite("Klien API /v1 (SDD §8.5, draf hingga ADR-0014)")
struct APIClientTests {
    let base = URL(string: "https://api.example.test")!

    @Test func problemJsonDipetakan() async {
        let transport = FakeTransport(status: 409, body: #"{"type":"ENR-LIMIT","title":"Batas kartu","status":409}"#, contentType: "application/problem+json")
        let client = APIClient(baseURL: base, transport: transport)
        await #expect(throws: ANError.cardLimitReached) {
            try await client.submitCredentialKey(enrollmentID: "E1", channel: .ble, publicKey: Data([0x04]), idempotencyKey: UUID())
        }
    }

    @Test func problemLainDiteruskan() async {
        let transport = FakeTransport(status: 403, body: #"{"type":"ENR-ATTEST-FAILED","status":403}"#, contentType: "application/problem+json; charset=utf-8")
        let client = APIClient(baseURL: base, transport: transport)
        await #expect(throws: ProblemDetails(type: "ENR-ATTEST-FAILED", title: nil, status: 403)) {
            try await client.submitCredentialKey(enrollmentID: "E1", channel: .ble, publicKey: Data([0x04]), idempotencyKey: UUID())
        }
    }

    @Test func postMembawaIdempotencyKey() async throws {
        let transport = FakeTransport(body: provisionedJSON)
        let key = UUID()
        _ = try await APIClient(baseURL: base, transport: transport)
            .submitCredentialKey(enrollmentID: "E1", channel: .ble, publicKey: Data([0x04, 0x01]), idempotencyKey: key)
        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/enrollments/E1/credentials")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["channel": "ble", "public_key": "BAE="])
    }

    @Test func provisionedCredentialDecode() async throws {
        let credential = try await APIClient(baseURL: base, transport: FakeTransport(body: provisionedJSON))
            .submitCredentialKey(enrollmentID: "E1", channel: .ble, publicKey: Data([0x04]), idempotencyKey: UUID())
        #expect(credential.credentialID == Data(repeating: 0xC1, count: 16))
        #expect(credential.channel == .ble)
        #expect(credential.certificate == Data(repeating: 0xCE, count: 5))
        #expect(credential.notAfter == Date(timeIntervalSince1970: 1_794_096_000))
        #expect(credential.siteName == "Menara A")
        #expect(credential.zones == ["Lobi", "Lift"])
        #expect(credential.groupKeys == ["a1a2a3a4a5a6a7a8": [Data([0x04, 0x01]), Data([0x04, 0x02])]])
    }

    @Test func createEnrollmentMengirimPerangkatDanGedung() async throws {
        // Endpoint tracer backend R1 (pengganti sementara enrolment kartu fisik).
        let transport = FakeTransport(status: 201, body: #"{"enrollment_id":"6f1c2a9e-0000-4000-8000-000000000001"}"#)
        let id = try await APIClient(baseURL: base, transport: transport).createEnrollment(deviceID: "dev-1", siteID: "site-1")
        #expect(id == "6f1c2a9e-0000-4000-8000-000000000001")
        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/enrollments")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["device_id": "dev-1", "site_id": "site-1"])
    }

    @Test func createEnrollmentBatasKartu() async {
        let transport = FakeTransport(status: 409, body: #"{"type":"ENR-LIMIT","status":409}"#, contentType: "application/problem+json")
        await #expect(throws: ANError.cardLimitReached) {
            try await APIClient(baseURL: base, transport: transport).createEnrollment(deviceID: "dev-1", siteID: "site-1")
        }
    }

    @Test func configDecode() async throws {
        let transport = FakeTransport(body: #"{"enabled_channels":["ble","nfcHCE"],"wallet_program_enabled":false}"#)
        let config = try await APIClient(baseURL: base, transport: transport).fetchConfig()
        #expect(config == RemoteConfig(enabledChannels: [.ble, .nfcHCE], walletProgramEnabled: false))
        #expect(transport.lastRequest?.url?.path() == "/v1/config")
    }
}

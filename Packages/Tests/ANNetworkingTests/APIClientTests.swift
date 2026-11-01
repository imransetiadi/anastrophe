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

    @Test func notBeforeOpsionalDiDecode() throws {
        #expect(try ProvisionedCredential.decode(Data(provisionedJSON.utf8)).notBefore == nil)
        let withNotBefore = provisionedJSON.replacingOccurrences(of: #""not_after""#, with: #""not_before": "2026-11-01T00:00:00Z", "not_after""#)
        #expect(try ProvisionedCredential.decode(Data(withNotBefore.utf8)).notBefore == Date(timeIntervalSince1970: 1_793_491_200))
    }

    @Test func challengeMemakaiHexCredID() async throws {
        let nonce = Data(repeating: 0x4E, count: 32)
        let transport = FakeTransport(status: 201, body: #"{"nonce":"\#(nonce.base64EncodedString())","expires_at":"2026-11-01T00:02:00Z"}"#)
        let challenge = try await APIClient(baseURL: base, transport: transport).renewalChallenge(credentialID: Data(repeating: 0xC1, count: 16))
        #expect(challenge.nonce == nonce)
        #expect(challenge.expiresAt == Date(timeIntervalSince1970: 1_793_491_320))
        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path(percentEncoded: false) == "/v1/credentials/c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1:challenge")
    }

    @Test func renewMengirimNonceDanTandaTangan() async throws {
        let transport = FakeTransport(body: provisionedJSON)
        let key = UUID()
        let nonce = Data(repeating: 0x4E, count: 32), signature = Data(repeating: 0x51, count: 64)
        let renewed = try await APIClient(baseURL: base, transport: transport).renewCredential(credentialID: Data(repeating: 0xC1, count: 16), nonce: nonce, signature: signature, idempotencyKey: key)
        #expect(renewed.siteName == "Menara A")
        let request = try #require(transport.lastRequest)
        #expect(request.url?.path(percentEncoded: false) == "/v1/credentials/c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1:renew")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["nonce": nonce.base64EncodedString(), "signature": signature.base64EncodedString()])
    }

    @Test func pesanBuktiKepemilikan() {
        let challenge = RenewalChallenge(nonce: Data(repeating: 0x4E, count: 32), expiresAt: .now)
        let credentialID = Data(repeating: 0xC1, count: 16)
        #expect(challenge.message(credentialID: credentialID) == Data("ANP1-RENEW".utf8) + credentialID + Data(repeating: 0x4E, count: 32))
    }

    @Test func deleteCardMengirimBuktiKepemilikan() async throws {
        // FR-31, ADR-0026.
        let transport = FakeTransport(status: 204, body: "")
        let key = UUID()
        let credentialID = Data(repeating: 0xC1, count: 16), nonce = Data(repeating: 0x4E, count: 32), signature = Data(repeating: 0x51, count: 64)
        try await APIClient(baseURL: base, transport: transport).deleteCard(cardID: "6f1c2a9e-0000-4000-8000-000000000001", credentialID: credentialID, nonce: nonce, signature: signature, idempotencyKey: key)
        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path(percentEncoded: false) == "/v1/cards/6f1c2a9e-0000-4000-8000-000000000001")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["credential_id": credentialID.base64EncodedString(), "nonce": nonce.base64EncodedString(), "signature": signature.base64EncodedString()])
    }

    @Test func pesanHapusKartu() {
        let challenge = RenewalChallenge(nonce: Data(repeating: 0x4E, count: 32), expiresAt: .now)
        let credentialID = Data(repeating: 0xC1, count: 16)
        #expect(challenge.revokeMessage(credentialID: credentialID, cardID: "6F1C2A9E-0000-4000-8000-00000000000A")
                == Data("ANP1-REVOKE".utf8) + credentialID + Data(repeating: 0x4E, count: 32) + Data("6f1c2a9e-0000-4000-8000-00000000000a".utf8))
    }

    @Test func createEnrollmentMengirimPerangkatDanGedung() async throws {
        // Endpoint tracer backend R1 (pengganti sementara enrolment kartu fisik).
        let transport = FakeTransport(status: 201, body: #"{"enrollment_id":"6f1c2a9e-0000-4000-8000-000000000001"}"#)
        let key = UUID()
        let id = try await APIClient(baseURL: base, transport: transport).createEnrollment(deviceID: "dev-1", siteID: "site-1", idempotencyKey: key)
        #expect(id == "6f1c2a9e-0000-4000-8000-000000000001")
        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
        #expect(request.url?.path() == "/v1/enrollments")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["device_id": "dev-1", "site_id": "site-1"])
    }

    @Test func createEnrollmentBatasKartu() async {
        let transport = FakeTransport(status: 409, body: #"{"type":"ENR-LIMIT","status":409}"#, contentType: "application/problem+json")
        await #expect(throws: ANError.cardLimitReached) {
            try await APIClient(baseURL: base, transport: transport).createEnrollment(deviceID: "dev-1", siteID: "site-1", idempotencyKey: UUID())
        }
    }

    @Test func configDecode() async throws {
        let transport = FakeTransport(body: #"{"enabled_channels":["ble","nfcHCE"],"wallet_program_enabled":false}"#)
        let config = try await APIClient(baseURL: base, transport: transport).fetchConfig()
        #expect(config == RemoteConfig(enabledChannels: [.ble, .nfcHCE], walletProgramEnabled: false))
        #expect(transport.lastRequest?.url?.path() == "/v1/config")
    }
}

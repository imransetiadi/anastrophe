import ANCore
import Foundation
import Testing
@testable import ANNetworking

@Suite("Pencarian kode gedung (ADR-0044)")
struct SiteLookupTests {
    let base = URL(string: "https://api.contoh.test")!

    @Test func lookupMengirimKodeTernormalisasi() async throws {
        let transport = FakeTransport(body: #"{"site_id":"6f1c2a9e-0000-4000-8000-000000000001","name":"Menara Uji"}"#)
        let site = try await APIClient(baseURL: base, transport: transport).lookupSite(code: "7k2q-9xa4")
        #expect(site == SiteSummary(siteID: "6f1c2a9e-0000-4000-8000-000000000001", name: "Menara Uji"))
        let request = try #require(transport.lastRequest)
        let url = try #require(request.url)
        #expect(request.httpMethod == "GET")
        #expect(url.path() == "/v1/sites/lookup")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "code", value: "7K2Q9XA4")])
    }

    @Test func lookupMembawaKanalGedung() async throws {
        // ADR-0049: kanal efektif gedung; kanal yang tidak dikenal app diabaikan.
        let transport = FakeTransport(body: #"{"site_id":"s1","name":"Menara Uji","channels":["nfcHCE","x"]}"#)
        let site = try await APIClient(baseURL: base, transport: transport).lookupSite(code: "7K2Q9XA4")
        #expect(site.channels == [.nfcHCE])
        let legacy = try await APIClient(baseURL: base, transport: FakeTransport(body: #"{"site_id":"s1","name":"Menara Uji"}"#)).lookupSite(code: "7K2Q9XA4")
        #expect(legacy.channels == nil)
    }

    @Test func lookupTakDikenalMenjadiSiteCodeUnknown() async {
        let transport = FakeTransport(status: 404, body: #"{"type":"SITE-NOT-FOUND","status":404}"#, contentType: "application/problem+json")
        await #expect(throws: ANError.enrollmentRejected(.siteCodeUnknown)) {
            try await APIClient(baseURL: base, transport: transport).lookupSite(code: "7K2Q9XA4")
        }
    }

    @Test func lookupKodeRusakTanpaJaringan() async {
        let transport = FakeTransport(body: "{}")
        await #expect(throws: ANError.enrollmentRejected(.siteCodeUnknown)) {
            try await APIClient(baseURL: base, transport: transport).lookupSite(code: "7K2Q9XU4")
        }
        #expect(transport.lastRequest == nil)
    }
}

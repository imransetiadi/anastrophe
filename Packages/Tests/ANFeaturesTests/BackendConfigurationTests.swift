import Foundation
import Testing
@testable import ANFeatures

@Suite("Base URL API dari konfigurasi build")
struct BackendConfigurationTests {
    @Test func baseURLDariInfoPlist() {
        #expect(BackendConfiguration.apiBaseURL(infoValue: "https://api.contoh.test", arguments: []) == URL(string: "https://api.contoh.test"))
    }

    @Test(arguments: [nil, "", "  ", "bukan url", "ftp://x.test", "https://", "http://api.contoh.test"] as [String?])
    func baseURLKosongBerartiTidakAda(value: String?) {
        // Info.plist wajib https; nilai kosong ($(AN_API_BASE_URL) tidak diisi) berarti layanan belum ada.
        #expect(BackendConfiguration.apiBaseURL(infoValue: value, arguments: []) == nil)
    }

    @Test func argumenDebugMenimpaInfoPlist() {
        let url = BackendConfiguration.apiBaseURL(infoValue: "https://api.contoh.test", arguments: ["-ANAPIBaseURL", "http://127.0.0.1:8099"])
        #expect(url == URL(string: "http://127.0.0.1:8099"))
    }
}

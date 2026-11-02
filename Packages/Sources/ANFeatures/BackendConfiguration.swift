import Foundation

/// Alamat layanan API untuk enrolment. Domain produksi belum ditentukan (SDD §5.6, ADR-0014), jadi
/// nilainya datang dari build setting `AN_API_BASE_URL` lewat Info.plist `ANAPIBaseURL`; kosong berarti
/// layanan belum tersedia dan alur Tambah Kartu tidak menghubungi jaringan.
public enum BackendConfiguration {
    /// Info.plist harus `https` dengan host. Di DEBUG, `-ANAPIBaseURL <url>` (http atau https) menimpanya
    /// untuk lab dan e2e dengan backend lokal.
    public static func apiBaseURL(infoValue: String?, arguments: [String]) -> URL? {
        #if DEBUG
        if let index = arguments.firstIndex(of: "-ANAPIBaseURL"), arguments.indices.contains(index + 1),
           let url = url(arguments[index + 1], schemes: ["http", "https"]) {
            return url
        }
        #endif
        return infoValue.flatMap { url($0, schemes: ["https"]) }
    }

    private static func url(_ value: String, schemes: Set<String>) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}

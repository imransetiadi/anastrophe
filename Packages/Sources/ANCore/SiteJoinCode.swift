/// Kode gedung yang diketik penghuni untuk enrolment kartu fisik (ADR-0044): 8 simbol Crockford base32
/// tanpa I, L, O, U, ditampilkan `XXXX-XXXX`. Aturan normalisasi sama dengan server
/// (`store.NormalizeJoinCode`), sehingga kode yang tidak sah tidak perlu dikirim.
public enum SiteJoinCode {
    static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let length = 8

    /// Huruf besar, `-` dan spasi dibuang, `O` dibaca `0`, `I` dan `L` dibaca `1`; nil bila hasilnya
    /// bukan tepat 8 simbol alfabet.
    public static func normalized(_ input: String) -> String? {
        var result = ""
        for character in input.uppercased() {
            if character == "-" || character.isWhitespace { continue }
            let symbol: Character = switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character
            }
            guard alphabet.contains(symbol), result.count < length else { return nil }
            result.append(symbol)
        }
        return result.count == length ? result : nil
    }

    /// `7K2Q9XA4` → `7K2Q-9XA4`.
    public static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}

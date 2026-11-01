import Foundation

/// String lokal dari katalog modul ini (ID/EN).
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

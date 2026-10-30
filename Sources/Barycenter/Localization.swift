import Foundation

/// Winziger Lokalisierungs-Helfer. Die Schlüssel sind die deutschen Strings selbst,
/// daher braucht Deutsch (Basissprache) keine Tabelle — fehlende Schlüssel fallen auf
/// den Schlüssel zurück. Übersetzungen liegen in
/// `Localization/<lang>.lproj/Localizable.strings` und werden von build_app.sh ins
/// App-Bundle kopiert.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

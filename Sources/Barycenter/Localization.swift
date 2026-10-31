import Foundation

/// Tiny localization helper. The keys are the German strings themselves, so German
/// (the base language) needs no table — missing keys fall back to the key. Translations
/// live in `Localization/<lang>.lproj/Localizable.strings` and are copied into the app
/// bundle by build_app.sh.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

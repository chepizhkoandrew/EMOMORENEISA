import Foundation

/// Translate a UI string for the current interface language.
///
/// The English source string is used as the lookup key, so wrapping a literal
/// is minimal: `Text("Start")` → `Text(L("Start"))`. For English the key is
/// returned verbatim; for other languages the per-language table is consulted
/// with the key as fallback (so an untranslated string still renders in
/// English rather than showing a raw key).
///
/// Reading `LocalizationManager.shared.language` here is intentional: it
/// registers the SwiftUI observation dependency for any view calling `L(_:)`,
/// so localized views re-render the instant the language changes.
@discardableResult
func L(_ key: String) -> String {
    let language = LocalizationManager.shared.language
    switch language {
    case .english:
        return key
    case .ukrainian:
        return ukStrings[key] ?? key
    }
}

/// Interpolation-friendly variant: `L("Level %@", level)`.
/// The key (English source, with `%@`/`%d` placeholders) is translated first,
/// then arguments are substituted via `String(format:)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let template = L(key)
    return String(format: template, arguments: arguments)
}

/// Plural-aware localization. English uses `one`/`other`; Ukrainian selects the
/// correct one of its three forms (one / few / many) via the standard modulo
/// rules. Callers pass the plural template WITHOUT the count (the count is
/// substituted here via `%d` if the chosen form contains a placeholder).
func LPlural(
    _ count: Int,
    en one: String, _ other: String,
    uk ukOne: String, _ ukFew: String, _ ukMany: String
) -> String {
    let template: String
    switch LocalizationManager.shared.language {
    case .english:
        template = (count == 1) ? one : other
    case .ukrainian:
        let m10 = abs(count) % 10
        let m100 = abs(count) % 100
        if m10 == 1 && m100 != 11 {
            template = ukOne
        } else if (2...4).contains(m10) && !(12...14).contains(m100) {
            template = ukFew
        } else {
            template = ukMany
        }
    }
    return template.contains("%d") ? String(format: template, count) : template
}

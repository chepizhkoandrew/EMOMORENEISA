import Foundation

/// Languages the app interface can be presented in.
/// This is the *interface* language, distinct from the Spanish learning target.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case ukrainian = "uk"

    var id: String { rawValue }

    /// Name of the language shown in its own language (for a language picker).
    var nativeName: String {
        switch self {
        case .english:   return "English"
        case .ukrainian: return "Українська"
        }
    }

    /// A flag-ish glyph for compact display.
    var flag: String {
        switch self {
        case .english:   return "🇬🇧"
        case .ukrainian: return "🇺🇦"
        }
    }

    /// The value fed to the AI tutor as the student's native language, so
    /// grammar explanations happen in this language. Kept in English words on
    /// purpose because the prompt itself is written in Spanish/English.
    var tutorNativeLanguage: String {
        switch self {
        case .english:   return "English"
        case .ukrainian: return "Ukrainian"
        }
    }

    /// Resolve the best default interface language from the device's preferred
    /// languages. Ukrainian device ⇒ Ukrainian, otherwise English.
    static func resolveDefault(from preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferred {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? String(identifier.prefix(2)).lowercased()
            if code.lowercased() == "uk" { return .ukrainian }
            if code.lowercased() == "en" { return .english }
        }
        return .english
    }
}

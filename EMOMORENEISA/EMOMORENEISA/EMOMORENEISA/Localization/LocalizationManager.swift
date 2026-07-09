import Foundation
import Observation

/// Holds the current interface language and persists the user's choice.
///
/// Views read the current language indirectly through the global `L(_:)`
/// helper. Because this type is `@Observable` and `L(_:)` reads `language`
/// during a view's `body`, SwiftUI records the dependency and re-renders every
/// localized view instantly when the language changes — no app restart.
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    private static let storageKey = "app_language"

    private(set) var language: AppLanguage

    private init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.storageKey),
           let lang = AppLanguage(rawValue: stored) {
            language = lang
        } else {
            // First launch: pick the language closest to the user's device.
            let resolved = AppLanguage.resolveDefault()
            language = resolved
            defaults.set(resolved.rawValue, forKey: Self.storageKey)
        }
    }

    /// Change the interface language. Persists the choice. The app language is
    /// tied to the tutor's explanation language via `tutorNativeLanguage`.
    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.storageKey)
    }

    /// Native language passed to the AI tutor, derived from the app language.
    var tutorNativeLanguage: String { language.tutorNativeLanguage }
}

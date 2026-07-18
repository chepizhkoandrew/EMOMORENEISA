import Foundation

/// Ukrainian translations, keyed by the English source string.
///
/// The table is assembled from per-area partial dictionaries (declared in the
/// `Strings_uk_*.swift` files) so different UI areas can be maintained
/// independently. Add an entry to the relevant partial whenever an English
/// literal is wrapped in `L(...)`. If a key is missing, `L(...)` falls back to
/// the English source string. Only the app *interface* and native-language
/// explanations are translated — Spanish learning content stays Spanish.
let ukStrings: [String: String] = [
    ukCommonStrings,
    ukIntroStrings,
    ukHomeStrings,
    ukGameStrings,
    ukChatStrings,
    ukBillingStrings,
    ukParrotStrings,
    ukProfileStrings,
    ukMemorizeStrings,
    ukMusicStrings,
    ukSocialStrings,
].reduce(into: [String: String]()) { merged, partial in
    merged.merge(partial) { _, new in new }
}

// MARK: - Common (shared across the app)

let ukCommonStrings: [String: String] = [
    "Continue": "Продовжити",
    "Cancel": "Скасувати",
    "Done": "Готово",
    "Save": "Зберегти",
    "Close": "Закрити",
    "Back": "Назад",
    "Next": "Далі",
    "Skip": "Пропустити",
    "Retry": "Спробувати ще",
    "Loading…": "Завантаження…",
    "Settings": "Налаштування",
    "Language": "Мова",
    "App Language": "Мова застосунку",

    // Settings hub (two-level settings reached from the burger menu)
    "Words queue": "Черга слів",
    "User settings": "Налаштування користувача",
    "Seagull Steven's memory schedule & capacity": "Розклад і обсяг пам’яті Чайки Стівена",
    "Verb game tense, timer & hints": "Час, таймер і підказки гри з дієсловами",
    "Language, pronoun & voice replies": "Мова, займенник та озвучення",

    // Burger menu (Home + Chat screens)
    "Menu": "Меню",
    "Your Chats": "Ваші чати",
    "Profile": "Профіль",
    "Edit Goal": "Редагувати ціль",
    "Coming soon": "Скоро",
]

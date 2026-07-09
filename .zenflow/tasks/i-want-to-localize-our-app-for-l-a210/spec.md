# Technical Spec — Localization

## App layout (relevant)
- Real app target syncs `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/` (Xcode 16
  file-system synchronized groups, objectVersion 77). New files added to that
  folder are auto-included in the target — no `.pbxproj` edits needed.
- The root-level `App/`, `Views/`, `Engine/`, `Models/`, `Services/` folders
  are a stale duplicate NOT in the project. Do not edit them.
- No existing localization (`knownRegions = (en, Base)`; no `.strings`/`.xcstrings`).

## Approach: lightweight in-app localization (instant switch, no restart)

Rather than Apple `.lproj`/`AppleLanguages` (which needs a restart for a clean
in-app override), use a small self-contained manager + a Swift translation
table. This builds deterministically and switches instantly via SwiftUI
`@Observable` tracking.

### New files (under `.../EMOMORENEISA/Localization/`)
- `AppLanguage.swift` — `enum AppLanguage: String { case english = "en", ukrainian = "uk" }`
  with `displayName`, `nativeName`, and `tutorNativeLanguage` ("English"/"Ukrainian").
- `LocalizationManager.swift` — `@Observable final class LocalizationManager`
  singleton. `var language: AppLanguage` persisted in `UserDefaults`
  (`"app_language"`). `init` resolves default from `Locale.preferredLanguages`
  when unset. `func setLanguage(_:)` persists + updates tutor native language.
- `Localizable.swift` — global `func L(_ key: String) -> String`. Reads
  `LocalizationManager.shared.language` (this read registers the SwiftUI
  observation dependency, so every view calling `L(...)` re-renders on change).
  English returns the key verbatim; other languages look up the table and
  fall back to the key.
- `Strings_uk.swift` — `let ukStrings: [String: String]` mapping the English
  source string → Ukrainian. English-as-key keeps the refactor minimal:
  `Text("Start")` → `Text(L("Start"))`.

### Reactivity
`L()` accesses `LocalizationManager.shared.language` during `body` evaluation.
Because the manager is `@Observable`, SwiftUI records the dependency and
re-invokes the body when `language` changes. No `.id()` remount and no
environment injection required.

### Default detection
`Locale.preferredLanguages.first` languageCode == "uk" ⇒ `.ukrainian`, else
`.english`. Persist the resolved value on first run.

### Language picker UI
Add a language section/picker to the settings surfaces:
- `Memorize/Views/MemorizeSettingsView.swift` (chat/memorize settings)
- `Chat/Profile/ProfileView.swift` (profile screen)
The picker calls `LocalizationManager.shared.setLanguage(_:)`.

### Tutor tie-in
- `Chat/LLM/PromptBuilder.swift`: use
  `LocalizationManager.shared.tutorNativeLanguage` as the effective native
  language (authoritative, since app language ⇒ tutor language). This makes
  grammar explanations Ukrainian immediately for Ukrainian users.
- `Chat/Auth/AuthService.swift`: new profiles store
  `LocalizationManager.shared.tutorNativeLanguage` instead of hardcoded
  "English".
- Parrot translation pivot (`parrotScriptPrompt`): translate into the user's
  native language (keep JSON key name for parser compatibility).

## Content that stays Spanish (NOT touched)
- `topicSystemPrompt` / `visualSystemPrompt` Spanish tutor instructions.
- Verb/pronoun data, `es-ES` in `Services/SpeechService.swift`,
  `AVSpeechSynthesisVoice(language: "es-ES")`, TTS proxy Spanish audio.

## UI files to refactor (extract English literals → `L(...)`)
Intro/Onboarding, Home/ModeSelector, Game (Matrix/Results/SlotMachine),
Chat (Messages, Sessions, Auth, Billing, Parrot, Annotation, Profile),
Memorize (Hub/Stats/Vocabulary/SRS/Settings/Celebration). ~30 files.

## Verification
- `xcodebuild build` for the `EMOMORENEISA` scheme (Xcode 26.3 available).
- Manual sanity: default resolves correctly; toggling picker flips UI + tutor.

# Requirements — App Localization (Ukrainian first)

## Goal
Localize the Spanish-learning iOS app so the **interface** and the **tutor's
native-language explanations** are available in Ukrainian in addition to
English, with the user able to choose the language in-app. Ukrainian is the
first added locale; the architecture must make adding more languages easy.

## Confirmed decisions (from user)
1. **Scope**: Translate (a) the app interface/chrome, (b) the AI tutor's
   native-language explanations, and (c) the English translation-pivots in
   prompts (e.g. word/phrase translations) into Ukrainian.
   **Keep the Spanish learning content unchanged** — the tutor still speaks
   Spanish, verbs stay Spanish, Spanish TTS stays, and `es-ES` speech
   recognition stays (recognizing the student's spoken Spanish is the target).
2. **Default language**: If the device's preferred language is Ukrainian →
   default UI = Ukrainian; otherwise English. User can override in-app, and
   the override is remembered.
3. **Tutor tie-in**: Selecting Ukrainian as the app language also makes the AI
   tutor explain grammar in Ukrainian (app language ⇒ `nativeLanguage`).
4. **Delivery**: Build the full localization infrastructure (language picker +
   auto-default + tutor wiring) AND translate the entire UI to Ukrainian now.

## Functional requirements
- FR1: A `LocalizationManager` holds the current `AppLanguage` (`.english`,
  `.ukrainian`), persisted across launches.
- FR2: On first launch (no stored choice), resolve default from
  `Locale.preferredLanguages`.
- FR3: All user-facing UI strings resolve through the manager and update
  reactively when the language changes (no app restart).
- FR4: A language picker is reachable from the app's settings surfaces.
- FR5: The AI tutor's `nativeLanguage` follows the app language.
- FR6: Spanish learning content (tutor Spanish output, verbs, TTS, `es-ES`
  STT) is NOT affected.

## Non-goals (this iteration)
- Adding languages beyond English and Ukrainian.
- Localizing App Store metadata / marketing website.
- Translating dynamic AI-generated Spanish content.

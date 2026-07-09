# Auto

## Configuration
- **Artifacts Path**: {@artifacts_path} → `.zenflow/tasks/{task_id}`

## Agent Instructions

Ask the user questions when anything is unclear or needs their input. This includes:
- Ambiguous or incomplete requirements
- Technical decisions that affect architecture or user experience
- Trade-offs that require business context

Do not make assumptions on important decisions — get clarification first.

**Debug requests, questions, and investigations:** answer or investigate first. Do not create a plan upfront — the user needs an answer, not a plan. A plan may become relevant later once the investigation reveals what needs to change.

**For all other tasks**, before writing any code, assess the scope of the actual change (not the prompt length — a one-sentence prompt can describe a large feature). Scale your approach:

- **Trivial** (typo, config tweak, single obvious change): implement directly, no plan needed.
- **Small** (a few files, clear what to do): write 2–3 sentences in `plan.md` describing what and why, then implement. No substeps.
- **Medium** (multiple components, design decisions, edge cases): write a plan in `plan.md` with requirements, affected files, key decisions, verification. Break into 3–5 steps.
- **Large** (new feature, cross-cutting, unclear scope): gather requirements and write a technical spec first (`requirements.md`, `spec.md` in `{@artifacts_path}/`). Then write `plan.md` with concrete steps referencing the spec.

**Skip planning and implement directly when** the task is trivial, or the user explicitly asks to "just do it" / gives a clear direct instruction.

To reflect the actual purpose of the first step, you can rename it to something more relevant (e.g., Planning, Investigation). Do NOT remove meta information like comments for any step.

Rule of thumb for step size: each step = a coherent unit of work (component, endpoint, test suite). Not too granular (single function), not too broad (entire feature). Unit tests are part of each step, not separate.

Update `{@artifacts_path}/plan.md` if it makes sense to have a plan and task has more than 1 big step.

---

# Localization (Ukrainian first) — Implementation Plan

See `requirements.md` and `spec.md` in this folder for full detail.
Confirmed: translate UI + tutor native-language explanations + prompt
translation-pivots to Ukrainian; keep Spanish learning content; default from
device language (uk⇒Ukrainian else English) with in-app override; app language
ties to tutor native language; deliver full infra + full UI translation now.

### [x] Step: Investigation
- Mapped app structure, confirmed real target folder, no existing i18n,
  prompts already parameterize nativeLanguage, STT/TTS are Spanish learning
  content. Gathered decisions from user.

### [ ] Step: Localization infrastructure
- Add `Localization/AppLanguage.swift`, `LocalizationManager.swift`,
  `Localizable.swift` (global `L()`), `Strings_uk.swift`.
- Default detection from `Locale.preferredLanguages`; persist in UserDefaults.
- Add `uk` to project `knownRegions`.

### [ ] Step: Language picker + tutor tie-in
- Add language picker to `MemorizeSettingsView` and `ProfileView`.
- Wire `PromptBuilder` and `AuthService` to `tutorNativeLanguage`.
- Point parrot translation pivot at the native language.

### [ ] Step: Translate UI — intro, onboarding, home, mode selector, game
- Refactor literals to `L(...)` and add Ukrainian entries for:
  Intro (Typewriter, OnboardingCarousel), Home/ModeSelector, Game
  (GameMatrix, MatrixCell, Results, SlotMachine, SpinningWheel).

### [ ] Step: Translate UI — chat, auth, billing, parrot, annotation, profile
- ChatView, MessageBubble, ThreadSheet, Sessions (List/New), SignInView,
  Paywall, BillingInfo, Parrot (Player/WordGrid), Annotation, Profile.

### [ ] Step: Translate UI — memorize/SRS + verify
- Memorize Hub/Stats/Vocabulary/SRS/Settings/Celebration/Container.
- `xcodebuild build` compile-check; fix issues; mark plan complete.

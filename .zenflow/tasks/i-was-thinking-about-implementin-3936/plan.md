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

# Voice Onboarding Quiz — Implementation Plan

Spec: `./.zenflow/tasks/i-was-thinking-about-implementin-3936/spec.md`
Current phase: **tech design drafted, blocked on user answers to §12 open questions (Q1–Q10).** Do NOT start implementation steps below until those are answered.

### [x] Step: Draft tech design spec
- Explore existing chat / voice / profile pipeline
- Write `spec.md` covering flow, question wording, adaptive probing, data model, backend, submodule layout, edge cases
- List open questions for user approval (§12 Q1–Q10)

### [x] Step: Lock product decisions (§12 Q1–Q10)
- Q1: EN + UK, per-language quiz, shared engine
- Q2: 5 standard + 3 adaptive (Q6 on 5, Q7 on 6, Q8 on 7); wording drafted in spec §5
- Q3/Q5: same voice as intro slides / dog bubble (voice-tag pinned via `activeVoiceTag()`)
- Q4: medium-deep probing
- Q6: tap-to-start / tap-to-stop + live equalizer (Whisper-Flow style)
- Q7: **Gemini** (already in GCP cluster / existing `GEMINI_API_KEY`) — `gemini-2.5-flash` for probes (env `MODEL_ONBOARDING_PROBE`), `gemini-2.5-pro` for final synthesis (env `MODEL_ONBOARDING_SYNTHESIS`); cost line added to the Google Sheet
- Q8: same visual language as tutor chat + Professor Madrid dog illustrations in background
- Q9: no post-quiz review; instead a Profile → "About me" section with smoothed user-facing paraphrase (raw kept for tutor)
- Q10: extend existing `profileDigest` mechanism, no new injection path

### [x] Step: Approve v1.2 restructure + final wording (R1)
- [x] R1a — 7 standard questions (Q1..Q7), 2 finale (Q10/Q11), single fallback, reprompt, closing template — approved in EN + UK (UK he/she/they variants); Q3 = "what do you do", Q4 = "why Spanish", Q5 = "how long / how learning", Q6 = "self-rating + improvement priority", Q7 = "daily routine", Q7b (probe seed) = "one small random thing about yourself" (used as the sole fallback), Q10 = "imagine you already know Spanish enough to perform on national TV or sell pens on Wall Street — what changes in your life?", Q11 = "who do you like more, dogs or cats? Dogs, right? Tell me you like dogs more."
- [x] R1b — silent pre-form (name + pronoun He/She/They + quiz language EN/UK) approved as Phase A gate.
- [x] R1c — gender/pronoun engine (§0.2) approved: EN=1 variant, UK=3 variants, every new language must ship all 3 up front, `ESPProfile.userPronoun` flows into every chat system prompt.
- [x] R2 — background: SINGLE full-bleed image `onboarding_background.jpg` (attached "Tommy" photo, 1536 px, ~153 KB) used behind every question. Prior 3-photo rotation dropped; other placeholder poses removed.
- [x] R3 — renderer runs locally against live proxy, AACs committed to bundle (option a). CI deferred. Script must build `{lang}/{gender}/*.aac` and dedupe identical lines via content-hash into `shared_/`.
- [x] R4 — About me row hangs off existing `ProfileView.swift` pattern.
- [x] R5 — no skip button anywhere; quiz is mandatory. Mic-denied → keyboard fallback (still 11 questions).
- Spec bumped to v1.3 (approved + single-background).

### [x] Step: Backend endpoints + asset renderer
- Add `./server/src/onboardingPrompts.js` with the tone header + pass-1/pass-2 distillation prompts + synthesis prompt from spec §6.1 (both probes emit gendered text in the correct language directly)
- Add a small `geminiText()` helper in `./server/src/providers.js` that hits `generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` (reusing `GEMINI_API_KEY`) and returns parsed JSON
- Add `POST /v1/onboarding/probe` (utility class, JWT-gated, not billed) — inputs include `pronoun` and `quizLanguage`; dispatches to `gemini-2.5-flash`, validates JSON schema from spec §6.1.1, retries once on invalid JSON
- Add `POST /v1/onboarding/synthesize` (utility class, not billed) — dispatches to `gemini-2.5-pro`, validates the 4-field JSON from spec §6.1.3
- Add `GET /v1/voice/current` returning `activeVoiceTag()` from `./server/src/voicecache.js`
- Add `./server/scripts/render-onboarding-assets.js` to pre-render the 9 pre-recorded questions (Q1..Q7 + Q10 + Q11) + reprompt + fallback × {en/neutral, uk/he, uk/she, uk/they} as AAC via `/v1/tts`; dedupe identical text via content-hash into `shared_/` and write per-lang/per-gender `manifest.json` with the voice tag
- Add 24 h per-user rate limit on quiz-completion writes
- Add pricing sheet line: Gemini text tokens (probe ×2 + synthesis ×1) and Gemini TTS for on-the-fly Q8/Q9/closing

### [x] Step: Swift submodule scaffolding + models
- Create `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Onboarding/` folder in Xcode project
- Add `OnboardingModels.swift`, `OnboardingQuestionBank.swift`, `OnboardingStore.swift`, `GenderedString.swift` (the pronoun-variant helper used app-wide)
- Extend `ESPProfile` with `pronoun: Pronoun` (defaults .they for legacy profiles) + `onboarding: OnboardingProfile?` (backward-compatible `CodingKeys`)
- Wire into `LocalStudentProfile` SwiftData mirror
- Ship pre-rendered per-lang/per-gender assets into `Onboarding/Assets/` bundle
- Add `PreOnboardingFormView.swift` (SwiftUI form: name + pronoun picker + quiz-language segmented control; Continue disabled until all set)

### [x] Step: Analyst + audio pipeline
- Add `OnboardingAnalyst.swift` wrapping the two new proxy endpoints
- Add `OnboardingAudioPlayer.swift` (asset-or-TTS switcher, voice-tag check on launch)
- Add `OnboardingRecorderAdapter.swift` around existing `AudioRecorder` with silence-based auto-stop
- Add `OnboardingCoordinator.swift` state machine (Q1 → Q4 → probe1 → Q5 → probe2 → Q6 → synthesize → closing)

### [x] Step: UI + entry wiring
- Build `OnboardingView.swift` (waveform orb, progressive dots, subtitle strip, mic button, live level meter, transcript preview)
- Add "Type instead" fallback path
- Full-screen cover from `ModeSelectorView` when `authState.needsOnboarding == true`
- Consent + mic-permission sheet + privacy explainer

### [x] Step: Post-TestFlight bug bash (audio isolation + intro-style redesign)
- Isolate onboarding audio scene: OnboardingContainerView stops OnboardAudioManager + fades out BackgroundMusicPlayer on appear; restores on disappear
- Redesign OnboardingView: GameBackground + DreamParticlesView + `onboard_dog` character; single mic control (visible only during .awaitingAnswer / .recording); question subtitle visible during playback with multi-line wrap; removed "Press to reply" hint text
- Align PreOnboardingFormView background with intro-slide style (GameBackground + DreamParticlesView)
- Fastlane beta build uploaded to TestFlight

### [x] Step: Tutor plumbing + QA
- Append `tutorCheatSheet` into `PromptBuilder`'s system prompt (per §12 Q10)
- Verify appended digest in `ESPProfile.profileDigest`
- Run 5-persona QA loop; confirm tutor references ≥ 2 slots in first 5 turns
- Ship behind a Supabase feature flag, new signups only

### [x] Step: Round 13 UX refinements (post-build-79)
- PreOnboardingFormView: language picker converted from horizontal segmented control to a 1-column vertical list (scales to more languages)
- Drop Q1 (name + country/city) from the quiz flow — name is captured on the pre-form. `OnboardingSlot.q1` kept in the enum but removed from `OnboardingCoordinator.flow`; `OnboardingQuestionBank.progressCount` = 10; `indexForProgress` mapping rewritten to start at Q2
- New `.reviewingAnswer(slot)` phase in OnboardingCoordinator — stopping the mic no longer auto-advances; the user sees the captured transcript with a forward arrow and taps to confirm
- New `confirmAndAdvance()` + `goBackOneSlot()` + `canGoBack` on OnboardingCoordinator; back arrow in the top-left of OnboardingView returns to prior slot with its transcript loaded (or replays its question if none)
- `OnboardingStore.recordAnswer` de-dupes on slot key; invalidates cached probes when a Q7-or-earlier slot is re-recorded
- OnboardingCoordinator caches Q8/Q9 probes — navigating back+forward does not re-bill Gemini
- Unified action orb: ONE 150×150 circle at a fixed position/size; content swaps between `PulsingEqualizerView` (animated bars while tutor speaks / closing), `LiveEqualizerView` (recorder-level driven while user is recording), spinner (thinking/transcribing), and mic icon (awaiting / reviewing / ready to re-record). Replaces the split waveformOrb + separate 82pt mic button that clashed with the dog avatar
- STT bias loosened: `sttLanguageOverride = nil` (auto-detect) with a prompt that lists native + Spanish + English so mixed / code-switched answers transcribe correctly

### [x] Step: Round 14 bug bash (transcript scroll, 25s cap, interrupt, Q5 split, prefetch, Q10 shortened, back/forward regression)
- OnboardingView: transcript wrapped in ScrollView, `lineLimit(10)`, `maxHeight: 200`; countdown badge (timer icon + red at ≤5s) rendered directly beneath the action orb; `.playingQuestion` added to `orbTappable`
- OnboardingCoordinator: added `recordingSecondsRemaining` + `maxRecordingSeconds = 25` + `recordingTimer`; `startRecordingCountdown` / `cancelRecordingCountdown`; refactored `toggleMic` to `startRecording` / `finishRecording` helpers; timer auto-invokes `finishRecording` at 0
- Interrupt-question-to-answer: `.playingQuestion(slot)` in `toggleMic` awaits `player.fadeOutAndStop(duration: 0.25)` then starts recording
- OnboardingAudioPlayer: added `fadeOutAndStop(duration:)` (10-step volume ramp then hard stop); split `playDynamic` into `prefetchDynamic(text:) -> URL?` + `playPrefetched(url:)` so network delay surfaces as `.thinking` before playback
- OnboardingCoordinator.runNext: for bundled/dynamic questions, set `phase = .thinking` while fetching then swap to `.playingQuestion` right at playback start
- OnboardingSlot: added `.q5b` case; `progressCount = 11`; `indexForProgress` mapping extended; Q5 now = rate 3 skills separately (listening/speaking/reading), Q5b = what to improve most
- OnboardingQuestionBank: shortened Q10 EN "Imagine you already speak Spanish fluently — what changes in your life?" + UK equivalent for all 3 pronoun banks
- Back/forward regression fix: `runNext(from:)` now short-circuits to `.reviewingAnswer(slot)` when `store.transcripts[slot]` is already populated, so back → forward preserves captured answers instead of re-playing the question
- Server `onboardingPrompts.js`: q5b added to transcript blocks in probe pass 1, probe pass 2, and synthesis; synthesis header updated to "12-question"; `ONBOARDING_QUIZ_VERSION` bumped 3 → 4
- Server `render-onboarding-assets.js`: `q5b` inserted in EN + UK he/she/they banks AND in the `SLOTS` array so the asset renderer emits the new file
- xcodebuild Debug simulator build: **BUILD SUCCEEDED**

### [x] Step: Round 15 UX polish (pre-form split + orb anchor + bigger transcript)
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Onboarding/PreOnboardingFormView.swift`: rewritten as a 3-step wizard (step 0 = name, step 1 = pronoun, step 2 = language). Top bar with back arrow (step > 0) + 3-dot progress; per-step header ("¡Hola!" / "Nice to meet you!" / "Almost there"); Continue label swaps to "Start the quiz" on the last step; per-step validation gates Continue
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Onboarding/OnboardingView.swift`: orb now anchored — `orbSize` reduced 150 → 128 and equalizer bars 62/5/5 → 52/4.5/4.5 (mic 46 → 40) so the button never crowds the dog; added `reviewSlotHeight = 220` reserved below the orb regardless of phase so the orb position is IDENTICAL across speaking, recording, thinking, reviewing states; layout Spacers reordered so the orb sits above the dog's head instead of overlapping it
- Transcript polish: font 15 → 17 (weight .medium), opacity 0.9 → 0.95, `ScrollView(.vertical, showsIndicators: true)` with `maxHeight: 172` — long answers now scroll inside the fixed card slot without pushing the orb
- xcodebuild Debug simulator build: **BUILD SUCCEEDED**

### [x] Step: Round 16 Smart multi-axis level (Current / Listening / Speaking / Grammar / Goals) + TestFlight
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Onboarding/OnboardingModels.swift`: added `SkillBand` (band + note) and `StudentLevelBreakdown` (overall_band, current_state, listening, speaking, grammar, goals[]) with snake_case CodingKeys mapping to server; `OnboardingProfile.levelBreakdown: StudentLevelBreakdown?` added (optional so legacy quiz payloads still decode)
- `./server/src/onboardingPrompts.js`: extended `synthesisPrompt` JSON schema with full `level_breakdown` block — overall_band (A1–C2|unknown), current_state prose, per-skill listening/speaking/grammar objects (band + one-sentence note), and 2–5 English goals bullets derived from Q5b + Q3; evidence-weighting rules: observed speaking outweighs self-rating, `unknown` is a valid response, CEFR band definitions; bumped `ONBOARDING_QUIZ_VERSION` 4 → 5
- `./server/src/index.js`: `/v1/onboarding/synthesize` now normalises Gemini's snake_case `level_breakdown` into stable camelCase `levelBreakdown` on the wire (safe defaults per skill, goals capped at 6)
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Chat/Network/ProxyClient.swift`: `OnboardingSynthesisResult` extended with `levelBreakdown: StudentLevelBreakdown?`; parsed from `json["levelBreakdown"]` with nil fallback when server omits (older payloads)
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Onboarding/OnboardingStore.swift`: `buildProfile` now passes `levelBreakdown: syn.levelBreakdown`; default quiz version bumped 3 → 5
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Chat/Profile/StudentProfile.swift`: `profileDigest` injects the multi-axis breakdown into the tutor system prompt — includes Current state, per-skill bands + notes, and up to 5 goals bullets
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Chat/LLM/PromptBuilder.swift`: `topicSystemPrompt` now surfaces "CEFR X (speaking Y, listening Z, grammar W)" as the level string when a breakdown exists; `levelCeiling` switch replaced by CEFR-band ceiling derived from observed speaking (A1: 3–4 short frases → C1/C2: sin límite) with legacy `.beginner/.intermediate/.advanced` fallback
- `./EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Chat/Profile/ProfileView.swift`: `levelSection` rewritten — when a breakdown exists shows a stacked card with 4 skill rows (Current state / Listening / Speaking / Grammar), each with a yellow CEFR band chip and an English note line, plus a Goals divider listing every bullet; legacy 3-button Beginner/Intermediate/Advanced picker retained only as fallback until the user completes onboarding, with a hint line pointing to the voice onboarding
- xcodebuild Debug simulator build: **BUILD SUCCEEDED**
- Fastlane `beta` lane launched (archive → export → TestFlight upload); Railway auto-redeploys `server/` from `main` on push

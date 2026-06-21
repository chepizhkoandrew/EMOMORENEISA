# Loro Memorize — iOS Implementation Plan

## Context

The Chat Tutor + El Loro parrot pipeline already ships and works: `ParrotPhrase` (SwiftData `@Model`, 7 on-disk WAV `segmentPaths`), `ParrotService` (Gemini→OpenAI TTS that writes `1.wav`…`7.wav`), `LoopingParrotPlayer` (sequential segment playback with background audio, lock-screen Now Playing, remote commands, and an `isDone` flag), and `ParrotPlayerView` (the full player UI). "Loro Memorize" is a new third pillar that adds a passive spaced-repetition scheduler on top of this audio stack **without re-creating any audio code**. The authoritative spec is `./docs/srs-memorization-system.md` (v2.0); no Memorize/Loro Swift code exists yet, so the engine is greenfield while every audio touchpoint must reuse the shipped parrot pipeline.

The chosen approach is **device-first**: a new `MemoryCard` SwiftData `@Model` is the single source of truth for scheduling; it links to (never duplicates) `ParrotPhrase` via `sourceParrotId` and reuses the same 7 WAV paths in `audioSegmentPaths`. A card is born **only** when a user completes a full `LoopingParrotPlayer` loop run in chat (`player.isDone == true`); there is no "Teach Loro from scratch" entry point. The 13-step interval ladder and per-phase ×0.7 repetition decay are pure functions (unit-testable); the queue is a live SwiftData query (no persisted queue entity); Supabase mirrors stats/events only (no audio bytes). The plan front-loads a thin end-to-end vertical slice (card creation on loop completion → queue → minimal session player with auto-advance + background audio) so the feature is usable early, then layers stats, notifications, gamification, settings, and edge cases.

Key trade-offs/decisions honored exactly: (1) creation is chat-only and completion-gated — exit before `isDone` creates nothing; (2) `MemoryCard` and `ParrotPhrase` are independent records sharing the same WAV files (TTS paid once); (3) `repetitionsPerPhaseBase = player.totalLoops` (self-calibrating); (4) five user-visible **material** stages (Agua→Wood→Stone→Gold→Microchip), never creature evolution; (5) El Loro art is an asset-production task — plan named asset slots + emoji/SF-Symbol placeholders, never generate art in code.

**Spec reconciliation the implementer must know (locked decisions override the spec where they differ):** The spec §10 / §9 Gate 1 / E3 describe a "Teach Loro" first-exposure flow that creates cards at `exposureCount == 0` with `nextDueAt == nil`. The locked decisions supersede this: cards are created **only** post-completion with `exposureCount = 1` and `nextDueAt = now + 20 min` (spec §1.3 ¶"What triggers on §4.1"). Therefore in Phase 1: **Gate 1 (`unheardCount == 0`) is effectively always satisfied** and the first-exposure interstitial / N2 unheard-nudge do not apply. Keep `exposureCount == 0` representable in the model (for a possible future "Teach from scratch" path and for U6 re-teach math), but no creation path produces it. Flag this inline at the relevant steps.

**Source root for all Swift code:** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/`. New files live in a new `Memorize/` group with subfolders mirroring the existing `Chat/` layout (`Memorize/Model`, `Memorize/Engine`, `Memorize/Views`, `Memorize/Notifications`, `Memorize/Supabase`). Docs stay at repo-root `docs/`.

---

## Changes

### Phase 1 — Vertical slice (engine + minimum usable loop)

#### Step 1 — `MemoryCard` SwiftData model
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Model/MemoryCard.swift`.
- Define `@Model final class MemoryCard` mirroring spec §4.1, following the exact `ParrotPhrase`/`LocalChatSession` `@Model` conventions: `@Attribute(.unique) var id: UUID`; stored properties `content: String`, `translation: String`, `audioSegmentPaths: [String]`, `sourceWordId: UUID?`, `sourceParrotId: UUID?`, `exposureCount: Int`, `lastPlayedAt: Date?`, `nextDueAt: Date?`, `isArchived: Bool`, `repetitionsPerPhaseBase: Int`, `createdAt: Date`. Add `snoozedUntil: Date?` (for U2, additive vs spec but needed by Phase 3 — default `nil`) and `var isPaused: Bool = false` (U12 vacation) — both default-valued so SwiftData lightweight migration is automatic.
- Add a memberwise `init` (default `exposureCount = 1`, `isArchived = false`, `createdAt = Date()`) and a convenience `init(from phrase: ParrotPhrase, loops: Int)` that copies `phrase.segmentPaths` into `audioSegmentPaths`, sets `sourceParrotId = phrase.id`, `content = phrase.spanishPhrase`, `translation = phrase.englishTranslation`, `repetitionsPerPhaseBase = max(1, loops)`, `exposureCount = 1`.
- Add computed, **never-stored** helpers that delegate to the engine (Step 2): `var hasAudio: Bool { audioSegmentPaths.count == 7 }` (mirror `ParrotPhrase.hasAudio`), `var segmentURLs: [URL]` (mirror `ParrotPhrase.segmentURLs`). **Reuse note:** do not re-derive the parrot audio directory; these paths already point at `ParrotPhrase.parrotDir(for:)/N.wav`.
- **Why:** spec §4.1 — on-device source of truth; `exposureCount` is the single phase signal.
- **Risk:** mark only `id` as `.unique` (matches `ParrotPhrase`); do not add `.unique` to `sourceParrotId` (re-teach/U6 and duplicate handling may legitimately reference the same source over time).

#### Step 2 — Scheduler engine (pure functions + card mutation)
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Engine/MemorizeScheduler.swift`.
- Implement spec §6.2 verbatim as an `enum MemorizeScheduler` (stateless, static) so it is trivially unit-testable with no SwiftData:
  - `static let phaseIntervals: [TimeInterval]` (13 entries, exactly the spec values).
  - `static func nextDueAt(exposureCount: Int, from now: Date = Date()) -> Date?` — returns `nil` when `exposureCount >= 13` (archived), `now` clamp when out of low bounds; otherwise `now + phaseIntervals[exposureCount - 1]`.
  - `static func repetitionsThisPhase(exposureCount: Int, base: Int) -> Int` — `max(1, round(base * pow(0.7, exposureCount - 1)))` per spec §6.2 (guard `exposureCount > 0` → `base`).
  - `static func phaseLabel(exposureCount: Int) -> String` (internal "Learning 3" etc., spec §6.1) — used only for debug/analytics, never shown raw.
  - Inject `now` as a parameter (default `Date()`) on every time function so tests can pin the clock and to support E8 clock-jump tolerance.
- **Why:** spec §6 — interval ladder + decay are the engine's core, must be unit-tested independent of UI/persistence.

#### Step 3 — Five-stage material/horizon mapping
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Model/MemoryStage.swift`.
- `enum MemoryStage: CaseIterable { case agua, wood, stone, gold, microchip }` with:
  - `static func stage(forExposureCount: Int) -> MemoryStage` per spec §3.1 table (0–1→agua, 2–5→wood, 6–10→stone, 11–12→gold, ≥13→microchip).
  - `var horizonLabel: String` (`"~1 hour"`, `"~3 days"`, `"~1 month"`, `"~1 year"`, `"~5 years"`), `var materialName: String`, `var placeholderSymbol: String` (SF Symbol placeholder until art lands, e.g. `drop.fill`/`leaf.fill`/`mountain.2.fill`/`crown.fill`/`cpu.fill`), `var tokenColor: Color` (reuse `AppColors`/`GameColors` tokens).
- **Why:** spec §3 — the only phase language the user sees; centralizing it prevents the 13→5 mapping leaking into views.
- **Risk:** this is the only place the 13→5 compression lives; views must call it, never hardcode stage cutoffs.

#### Step 4 — `MemoryCardService` (creation, queue, gates, atomic update)
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Engine/MemoryCardService.swift`.
- `@Observable final class MemoryCardService` (match `ParrotService`'s `@Observable` convention) holding a `ModelContext` (passed in, as views get it via `@Environment(\.modelContext)`).
- Methods:
  - `func createCard(from phrase: ParrotPhrase, loops: Int) -> MemoryCard?` — **the creation gate.** Guard `phrase.hasAudio` (7 segments). Duplicate check (E11): if a non-archived `MemoryCard` already has `sourceParrotId == phrase.id`, return it without inserting. Otherwise build `MemoryCard(from:loops:)`, set `nextDueAt = MemorizeScheduler.nextDueAt(exposureCount: 1)` (now + 20 min), insert into context, `try? context.save()`, emit a `scheduled` Supabase event (Step 13, no-op stub in Phase 1), `glog("🧠 MEM", ...)`. Returns the card so the caller can show the toast.
  - `func buildQueue(sessionCap: Int = 20, now: Date = Date()) -> [MemoryCard]` — fetch via `FetchDescriptor<MemoryCard>` then filter/sort **in Swift** exactly per spec §8 (not all predicates compose in `#Predicate`): `!isArchived && !isPaused && nextDueAt != nil && nextDueAt! <= now`, sort by `exposureCount` asc, then most-overdue first, then stable shuffle within same urgency (extract the `prefix(sessionCap)` + `shuffledWithinSameUrgency` semantics inline). Clamp negative/jumped clocks to "due now" (E8).
  - `func onVisitDidComplete(_ card: MemoryCard, now: Date = Date())` — spec §7 atomic update: `exposureCount += 1`; `lastPlayedAt = now`; if `exposureCount >= 13` → `nextDueAt = nil`, `isArchived = true`, fire microchip celebration hook (Phase 2 stub) ; else `nextDueAt = MemorizeScheduler.nextDueAt(exposureCount:)`. `try? context.save()`; emit `played` event.
  - Derived metrics (spec §9.1, computed, not stored): `unheardCount`, `activeLearningCount` (`exposureCount` 1–5), `newTodayCount` (device-local midnight via `Calendar.current.startOfDay`), `nearTermLoad` (count of simulated visits due in next 7 days). Implement `nearTermLoad` by walking each non-archived card forward through `MemorizeScheduler.nextDueAt` until it exceeds `now + 7d`.
  - Capacity gates (spec §9): `enum GateResult { case ok; case blocked(GateFailure) }` and `func checkGates(settings:) -> GateResult` checking Gate 1→4 in order. **Phase 1 reality:** Gate 1 passes by construction (no `exposureCount == 0` cards exist); still implement it for completeness. Gates are consumed by the (future) creation UI — in the chat-only Phase 1 slice, gates do **not** block `createCard(from:)` (that is the spec's deliberate "completion is the signal" behavior, §1.3); wire gate enforcement to the Hub's add-affordance later.
- **Why:** spec §7, §8, §9 — central engine the views and notifications consume.
- **Risk (DUPLICATION):** do **not** create any audio playback, TTS, or file-writing logic here. Audio is owned by `LoopingParrotPlayer`/`ParrotService`. This service only mutates card scheduling state.

#### Step 5 — Register `MemoryCard` in the SwiftData schema
- **Modify** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/EMOMORENEISAApp.swift`.
- Add `MemoryCard.self` to the `Schema([...])` array (currently `LocalStudentProfile`, `LocalChatSession`, `LocalChatMessage`, `ParrotPhrase`).
- **Why:** spec §1.2 / §4.1 — card persistence. All new optional/default-valued fields keep migration lightweight (automatic).
- **Risk:** the container uses `try!`; a non-default-initializable new required property would crash on launch. Keep all additive fields default-valued (enforced in Step 1).

#### Step 6 — Card-creation hook in the existing player
- **Modify** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Chat/Parrot/ParrotPlayerView.swift`.
- Add `@State private var memoryToast: Bool = false` and a `MemoryCardService` built from `modelContext`.
- Add `.onChange(of: player.isDone)` on the root `ZStack`: when it transitions to `true`, call `service.createCard(from: phrase, loops: player.totalLoops)`; on non-nil result set `memoryToast = true` and show a transient banner *"This phrase went to Loro's memory 🧠"* (spec §1.3 step 3, §3.2 toast). Auto-dismiss after ~2.5s.
- **Integration point:** `player.isDone` is set `true` by `LoopingParrotPlayer.advanceLoop()` when `currentLoop >= totalLoops` (`LoopingParrotPlayer.swift:133`) and on skip-to-end (`:74`). `player.totalLoops` is the user's chosen loop count → becomes `repetitionsPerPhaseBase` (spec §1.3 step 89, §5.2).
- **Risk (DOUBLE-FIRE):** `isDone` can be set from both `advanceLoop()` and `skipToNextSegment()`, and the manual replay button calls `player.start(...)` again (`ParrotPlayerView.swift:289-291`) which resets `isDone = false` then can re-complete. `createCard` MUST be idempotent per `sourceParrotId` (handled by the duplicate check in Step 4) so a replay does not create a second card. Use `.onChange(of:)` (fires only on transition), not a `body`-derived check.
- **Reuse note:** do not modify `LoopingParrotPlayer`; the `isDone` signal already exists. Do not add audio code here.

#### Step 7 — Minimal Memorize entry + Hub (Due Now only)
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Views/LoroMemorizeHubView.swift`.
- Phase-1 minimal Hub (spec §11.2, trimmed): `AppBackground()` + full-body El Loro placeholder (emoji `🦜` or named asset slot `Image("loro_idle")` with graceful fallback) + "El Loro knows N words" (count of `isArchived` cards) + a golden **"Loro Memorize!"** primary CTA (reuse the `verbGameCard` button styling from `ModeSelectorView.swift:225`). Below it, a simple Due-Now list from `service.buildQueue()` showing each card's `content`, `MemoryStage.horizonLabel`, and per-card progress (`exposureCount`/13). CTA opens `SRSPlayerView` (Step 8) via `fullScreenCover`.
- Use `@Environment(\.modelContext)`, build `MemoryCardService` in `.task`/`init`. Empty Due-Now → simple "nothing due" text (full empty state is Phase 2, spec §15.2).
- **Modify** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Home/ModeSelectorView.swift`: add a third **"LORO MEMORIZE"** card beneath `verbGameCard` (clone the `verbGameCard`/`chatTutorCard` ZStack-gradient-button pattern, `:225`/`:177`), with a live Due-Now count badge. Present `LoroMemorizeHubView` via a new `@State private var showMemorize` + `.fullScreenCover` (mirror the existing `showChat` pattern at `:69`). Memorize needs no auth gate (data is local), unlike `chatDestination`.
- **Why:** spec §11.1 — Memorize as third pillar; the Hub is the 90%-case surface.
- **Risk:** `ModeSelectorView` vertical space is tight (dog + 2 cards in a `GeometryReader`). Add the card inside the existing `VStack` with a `Spacer(minLength:)` rather than restructuring the dog/chat ZStack.

#### Step 8 — Session player reusing `LoopingParrotPlayer`
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Views/SRSPlayerView.swift`.
- Drive playback with a **new lightweight session coordinator** that owns ONE `LoopingParrotPlayer` instance and the `[MemoryCard]` queue. Two viable approaches — choose **(A)** for Phase 1:
  - **(A) Reuse `LoopingParrotPlayer` per card by wrapping a transient `ParrotPhrase`-like input.** `LoopingParrotPlayer.start(phrase:loops:)` requires a `ParrotPhrase` (`LoopingParrotPlayer.swift:19`, reads `phrase.hasAudio`/`phrase.segmentURLs`). Two sub-options:
    - Resolve the real `ParrotPhrase` by `card.sourceParrotId` from SwiftData and pass it to `player.start(phrase:, loops: MemorizeScheduler.repetitionsThisPhase(...))`. Preferred — zero audio duplication, real Now Playing metadata.
    - If the source phrase was deleted, reconstruct a transient `ParrotPhrase` from `card.audioSegmentPaths` (set `segmentPaths` directly) — the WAVs still exist on disk.
- Per-card flow: compute `loops = MemorizeScheduler.repetitionsThisPhase(exposureCount: card.exposureCount, base: card.repetitionsPerPhaseBase)`, `player.start(phrase:, loops: loops)`. Observe `player.isDone`; on completion call `service.onVisitDidComplete(card)`, then **auto-advance** to the next queue card (spec §12.1) and `player.start` the next; when queue exhausts, show a minimal end-of-session summary (full summary is Phase 3).
- UI: reuse `ParrotPlayerView`'s structure for the now-playing word, the `segmentLabel` 7-part labels (`ParrotPlayerView.swift:232-248`), within-word "Repetition k of N", and session progress "Word i of M". Reuse `AppBackground`, `AppColors`.
- **Background/lock screen:** already provided by `LoopingParrotPlayer` (`AVAudioSession(.playback)`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` at `:84,:139,:153`) and the `audio` UIBackgroundMode (`Info.plist:17`). Phase 1 inherits single-phrase Now Playing for free; extending remote next/prev to **queue-level** word skipping is Phase 3 (spec §12.1, §19).
- **Why:** spec §12.1, §22 Phase 1 — passive listening core with auto-advance.
- **Risk (DUPLICATION — critical):** do NOT write a new audio player, segment loop, or `AVAudioPlayer` code. Reuse `LoopingParrotPlayer` as-is. The only new logic is the **queue/auto-advance coordinator** around it. A naive implementer will re-implement segment looping — explicitly forbidden.
- **Risk:** `LoopingParrotPlayer` is single-instance/single-phrase; restart it per card (call `stop()` then `start()`), do not instantiate one player per card.

#### Step 9 — N1 daily due notification (minimal)
- **Create** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Memorize/Notifications/MemoryCardNotificationService.swift`.
- Phase 1 scope: request `UNUserNotificationCenter` authorization (no notification permission code exists yet — Info.plist already has `aps-environment` via entitlements and `remote-notification` background mode at `Info.plist:16`), and schedule **N1** — a daily local notification ("🦜 El Loro is waiting — N words are ready", spec §14.1) at a default hour, batched (one notification, aggregate count). Reschedule on app foreground using `service.buildQueue().count`.
- Add a deep-link payload so tapping opens the Hub/Player (wire the navigation in Phase 3; Phase 1 just opens the app).
- **Why:** spec §14 / §22 Phase 1 — a passive SRS is useless without N1.
- **Risk:** permission priming should ideally follow the first "Microchip" moment (spec §14.2); for Phase 1 a simple request on first Hub visit is acceptable — note as a Phase 4 refinement.

---

### Phase 2 — Make it stick (metaphor, vocabulary, celebration, empty states)

#### Step 10 — Material/horizon UI components + asset slots
- **Create** `Memorize/Views/Components/MaterialTokenView.swift`, `HorizonStripView.swift` (spec §3.4: 5-stop strip 1h·3d·1mo·1yr·5yr), per-card 13/5 progress indicator.
- **Create** asset slots in `Assets.xcassets`: `loro_idle`, `loro_listening`, `loro_happy`, `loro_excited`, `loro_teaching`, `loro_sleeping`, `loro_sad` (spec §2.2) and 5 material token images — define a `LoroAsset` enum that returns the named image **with an SF-Symbol/emoji fallback** so the app builds and runs before art is delivered. Art production itself is out-of-code (spec §2, §22 Phase 2 dependency).
- **Why:** spec §3, §3.4 — the metaphor is the retention engine.

#### Step 11 — Microchip celebration + hero counter
- **Create** `Memorize/Views/MicrochipCelebrationView.swift`. Triggered from `onVisitDidComplete` archive branch (Step 4 hook). Reuse `ConfettiView` (`DesignTheme.swift:178`) for milestone counts only; success haptic; Madrid copy (spec §3.2). Material transmutation animation with a Reduce-Motion static fallback (spec §19).
- **Why:** spec §3.2 — the signature moment.

#### Step 12 — El Loro's Vocabulary screen + 3-tab container
- **Create** `Memorize/Views/LoroVocabularyView.swift` — material-token grid via `FlowLayout` (`Chat/Parrot/FlowLayout.swift:3`), tap-to-replay (non-counting, U9 → calls `player.start` but never `onVisitDidComplete`), filter/sort/search/share (spec §12.2).
- **Create** `Memorize/Views/MemorizeContainerView.swift` — 3-tab layout (Hub · Vocabulary · Progress) + Settings gear (spec §11.1); make `ModeSelectorView` present this container instead of the bare Hub.
- Empty states (spec §15.2): cold start, nothing due (sleeping Loro — a good state), all mastered, paused. Streak bookkeeping + N3/N4 notifications.
- **Why:** spec §12.2, §11.1, §15.2, §17.

---

### Phase 3 — Make it whole (management, stats, settings, resilience)

#### Step 13 — Supabase stats mirror (no audio bytes)
- **Modify** `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Chat/Supabase/SupabaseSyncService.swift` (extend the existing `.shared` singleton, `SupabaseSyncService.swift:5`).
- **Create** `Memorize/Supabase/RemoteMemoryCard.swift` — a `Codable` struct with `CodingKeys` snake_case mapping, exactly mirroring the `RemoteChatSession` pattern (`ChatSession.swift:21-45`). Fields: `id`, `userId`, `content`, `exposureCount`, `nextDueAt`, `isArchived`, `lastPlayedAt`, `deviceId`, `updatedAt`. **No `audioSegmentPaths` bytes** (paths-as-strings reference only, spec §1.2/§4.2).
- Add `func upsertMemoryCard(...)` and `func emitMemoryEvent(_ event: RemoteMemoryEvent)` (events: scheduled/played/skipped/snoozed/status-transition, spec §4.2) following the existing `upsert`/`insert`...`.execute()` + `glog("☁️ SYNC")` error pattern. Wire `MemoryCardService` event emitters (stubbed in Step 4) to these.
- Conflict resolution (E13): on fetch/merge, prefer `max(exposureCount)` + `latest(lastPlayedAt)` (spec §1.2, §18 E13). Implement a `reconcile(local:remote:)` helper.
- **Why:** spec §1.2, §4.2, §18 E13 — lightweight monitoring + cross-device.
- **Risk (DUPLICATION):** never push WAV bytes to Supabase. Audio stays on-device.

#### Step 14 — Card management actions (U1–U13)
- Extend `MemoryCardService` + Hub swipe actions / card detail (spec §13): U1 skip (session-only, no `exposureCount` change), U2 snooze (`snoozedUntil`/advance `nextDueAt`, persisted), U3 "already knows" (jump to archived, confirm modal), U4 delete (confirm; frees Gate 2), U5 edit/regenerate via `ParrotService.generate` (reuse, no new TTS), U6 re-teach archived → reset to `exposureCount = 6` Review-tier (spec D4), U7 clear queue, U9 non-counting replay, U12 vacation/pause (`isPaused`/freeze `nextDueAt`), U13 completed-visit definition (already in Step 4/8).
- **Risk:** U5 regenerate must reuse `ParrotService.generate(phrase:level:)` (`ParrotService.swift:22`) and overwrite the same WAV paths — no parallel TTS path.

#### Step 15 — Progress & Stats + Settings
- **Create** `Memorize/Views/LoroStatsView.swift` (spec §12.3): pipeline 5-segment bar, **forecasted-forgettingness table** (sorted soonest-first, grouped by horizon bucket), activity chart, forecast card (uses `nearTermLoad`), milestones. All computed on demand.
- **Create** `Memorize/Views/MemorizeSettingsView.swift` (spec §16.1): all 14 params via `@AppStorage` (mirror `HomeView.swift:59` `@AppStorage` usage) — `dailyNewLimit`, `maxActiveLearning`, `maxNearTermLoad`, `sessionSizeCap`, `repetitionsPerPhaseBase`, default loop multiplier, auto-advance, reminder time(s), quiet hours, per-type notification toggles, vacation, voice/speed, reset progress (double-confirm), replay onboarding. Wire `maxNearTermLoad` into Gate 4 and the "This week" capacity bar (spec §1.4, §11.3).
- Capacity indicator (spec §11.3) + inline gate-failure messages (spec §9.2) on the Hub add-affordance.

#### Step 16 — Platform resilience + remaining notifications
- Extend `LoopingParrotPlayer` queue-level remote commands (next/prev = next/prev **word**, Now Playing word + El Loro artwork) — spec §12.1/§19. Add `AVAudioSession.interruptionNotification` + `routeChangeNotification` handling (pause; interrupted visit doesn't count — E5/E12). **Modify** `LoopingParrotPlayer.swift` minimally (add observers + a queue-aware delegate hook) — keep single-phrase behavior intact for Chat.
- Welcome-back/avalanche flow (E1), session overflow continuation (E2), clock-safety (E8/E9), audio pre-cache/offline (E4). Notifications N2 (only if a "Teach from scratch" path is ever added), N3/N5/N6/N7 + smart timing/quiet hours/batching (spec §14.2).

#### Step 17 — Gamification long-tail (Phase 4)
- Milestone badges 10/25/50/100/250, 100-word "Professor Loro" co-teacher narrative beat (badge + copy only, no art change), achievements, topic collections, share cards, weekly digest N7, CarPlay consideration (spec §17, §22 Phase 4).

---

## Verification

**Build & run:**
- Open `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA.xcodeproj` (or workspace) in Xcode; build for an iOS Simulator: `xcodebuild -scheme EMOMORENEISA -destination 'platform=iOS Simulator,name=iPhone 15' build`. There is no SwiftPM/`npm`/CLI lint in this repo; correctness is verified via Xcode build + XCTest.
- After Step 5, launch the app and confirm it does not crash on the SwiftData container init (`try!` in `EMOMORENEISAApp.swift`) — proves the schema migration is lightweight.

**Unit tests (pure engine — no SwiftData/UI needed):**
- **Create** a test target/file `MemorizeSchedulerTests.swift`. (No test target exists yet; add an XCTest target `EMOMORENEISATests` if absent.)
  - `MemorizeScheduler.repetitionsThisPhase`: base=10 over exposureCount 1…7 → `[10,7,5,4,3,2,1]`; base=4 → `[4,3,2,1,1,1]`; floor never below 1 (spec §5.2 examples). Input `(exposureCount:1,base:5)→5`.
  - `MemorizeScheduler.nextDueAt(exposureCount:from:)` with pinned `now`: exposureCount 1 → now+1200s; 5 → now+2 days; 13 → returns `nil` (archived).
  - `MemoryStage.stage(forExposureCount:)`: 1→agua, 2→wood, 6→stone, 11→gold, 13→microchip (boundaries 1/2, 5/6, 10/11, 12/13).
- **Create** `MemoryCardServiceTests.swift` using an in-memory `ModelContainer` (`ModelConfiguration(isStoredInMemoryOnly: true)`):
  - `createCard(from:loops:)`: given a `ParrotPhrase` with 7 segments and loops=8 → card with `exposureCount==1`, `repetitionsPerPhaseBase==8`, `nextDueAt≈now+20min`, `audioSegmentPaths==phrase.segmentPaths`, `sourceParrotId==phrase.id`. Calling twice with the same phrase → only ONE card (E11 idempotency — guards the Step 6 double-fire risk).
  - `onVisitDidComplete`: from `exposureCount==12` → `13`, `isArchived==true`, `nextDueAt==nil`. From `1` → `2`, `nextDueAt` set.
  - `buildQueue`: cards with past/future/nil `nextDueAt` and archived/paused → only due, non-archived, non-paused returned; ordered by `exposureCount` asc then most-overdue (spec §8). `prefix(sessionCap)` honored.
  - Derived metrics: `newTodayCount` respects device-local midnight; `activeLearningCount` counts only `exposureCount` 1–5.

**Manual / behavioral (UI):**
- Step 6/8 end-to-end: in Chat, build a parrot phrase, play a full loop run → on completion a *"went to Loro's memory"* toast fires and a card exists. Exit before completion → no card (locked decision 1). Open Home → "LORO MEMORIZE" card shows Due-Now badge after the 20-min interval (or temporarily shorten interval for testing). Tap "Loro Memorize!" → `SRSPlayerView` plays the 7-part construction `repetitionsThisPhase` times, auto-advances, and a completed visit increments the stage. Lock the screen → audio continues with Now Playing info (inherited from `LoopingParrotPlayer`).

---

## Conventions and Reference

- **SwiftData `@Model` shape:** `@Model final class` with `@Attribute(.unique) var id: UUID`; only `id` is unique. Reference: `Chat/Parrot/ParrotPhrase.swift:5-6`, `Chat/Sessions/ChatSession.swift:47-49`.
- **On-disk audio paths:** WAVs live at `ParrotPhrase.parrotDir(for: id)/N.wav` (1…7); `hasAudio` = `segmentPaths.count == 7`; `segmentURLs` maps paths→file URLs. `MemoryCard` must reuse these, not re-derive. Reference: `Chat/Parrot/ParrotPhrase.swift:13,26,28,32`.
- **The 7-part segment order** (one repetition): `[spanish, english, spanish, spanish, spanish, sentence1, sentence2]`. Reference: `Chat/Parrot/ParrotService.swift:111-121`. UI labels for the 7 segments: `Chat/Parrot/ParrotPlayerView.swift:232-248`.
- **Audio generation (reuse for U5 only):** `ParrotService.generate(phrase:level:)` writes the WAVs and is `@Observable`. Reference: `Chat/Parrot/ParrotService.swift:4,22,49`.
- **Loop-completion signal (the creation hook):** `LoopingParrotPlayer.isDone` becomes `true` in `advanceLoop()` when `currentLoop >= totalLoops` and in `skipToNextSegment()`. `totalLoops` is the user's chosen count. Reference: `Chat/Audio/LoopingParrotPlayer.swift:11-12,72-74,124-136`.
- **Player reuse (do not re-implement audio):** `LoopingParrotPlayer.start(phrase:loops:)` requires a `ParrotPhrase` and already configures `AVAudioSession(.playback)`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`. Reference: `Chat/Audio/LoopingParrotPlayer.swift:19-31,84-91,139-149,153-177`.
- **Player view integration pattern** (`.task` start, `.onDisappear` stop, manual-replay re-`start`): `Chat/Parrot/ParrotPlayerView.swift:37-52,289-291`.
- **SwiftData schema registration:** add models to the `Schema([...])` array; container built with `try!`, so new required fields must be default-valued. Reference: `EMOMORENEISAApp.swift:16-24`.
- **Home mode cards + presentation:** clone the `verbGameCard`/`chatTutorCard` ZStack-gradient-button and present a new surface via `@State` + `.fullScreenCover` like `showChat`. Reference: `Home/ModeSelectorView.swift:69-71,177-223,225-270`.
- **Design tokens:** `AppColors` (`backgroundTop`, `accent=.yellow`, `cardBackground`, `cardBorder`, `textPrimary/Secondary/Tertiary`), `AppBackground`, `ConfettiView`, `GameColors`. Reference: `Design/DesignTheme.swift:5-17,63-99,178`.
- **Flow grid (vocabulary tokens):** reuse `FlowLayout`. Reference: `Chat/Parrot/FlowLayout.swift:3`.
- **Supabase Remote model + sync:** `Codable` struct with snake_case `CodingKeys`; singleton `SupabaseSyncService.shared`; calls `supabase.from("table").upsert/insert(...).execute()` and logs failures via `glog`. Reference: `Chat/Sessions/ChatSession.swift:21-45`, `Chat/Supabase/SupabaseSyncService.swift:5,8-27`, `Chat/Supabase/SupabaseClient.swift:4-11`.
- **Logging:** `glog("🧠 MEM", "...")` tag+message helper. Reference: `Services/GameLogger.swift:6`.
- **Settings persistence:** `@AppStorage("key")` for user prefs. Reference: `Views/Home/HomeView.swift:59-60`.
- **Existing SM-2 word model (link, do not duplicate):** `WordEntry` already does day-based SM-2 in the profile and is a separate signal; `MemoryCard` is the passive scheduler and only references it via `sourceWordId`. Reference: `Chat/Profile/ProfileModels.swift:5-66`.
- **Background audio + push entitlement already configured:** `UIBackgroundModes` includes `audio` and `remote-notification`; entitlements set `aps-environment`. No new capability needed for background playback; only `UNUserNotificationCenter` authorization code is new. Reference: `Info.plist:14-18`, `EMOMORENEISA.entitlements:5-6`.

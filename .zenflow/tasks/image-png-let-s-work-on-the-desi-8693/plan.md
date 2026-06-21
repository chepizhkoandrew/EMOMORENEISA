# Design Transformation — "Professor Madrid's Academy"

## Vision
Transform IOSSPANISHGAME from a functional-but-minimal dark app into a vibrant, gamified Spanish
learning experience. Think Duolingo energy: big tactile elements, celebration moments, personality,
and color that communicates state instantly. Every screen should feel alive and opinionated.

## Design Language

### Color System (Game sections)
- **Sky Indigo** `(0.08, 0.07, 0.18)` → `(0.04, 0.04, 0.14)` — richer, more saturated background for game
- **Fiesta Gold** `Color.yellow` — primary interactive / active
- **Joker Coral** `Color.orange` — irregular verbs / wild cards
- **Plaza Verde** `Color.green` — correct answers / success
- **Torero Rojo** `Color.red` — missed answers / danger
- **Glass Surface** `Color.white.opacity(0.09)` + blur — cards and cells
- **Neon Glow** shadows on active states using accent colors

### Typography
- Section labels: uppercase tracked monospaced — keep; increase sizes
- Verb names / pronouns: bold, slightly larger than current
- Score / result numbers: black-weight, drop-shadow glow

### Motion Principles
- Every state change gets a spring or ease transition
- Correct answer: scale pop + glow flash
- Missed answer: horizontal shake
- Results screen: confetti rain (Canvas particles)
- Cells: active state pulses with subtle breathing scale

---

## Screens — What Changes

### [x] Step: Expand DesignTheme.swift
- Add `GameColors` namespace for saturated game-specific palette
- Add `GameBackground` view — deeper indigo gradient with star-dot field overlay
- Add `ConfettiView` — Canvas-based particle system (colored stars/dots) for Results
- Add `CellGlassBackground` helper — glass morphism surface for matrix cells

### [x] Step: ModeSelectorView → "The Hub"
- Full-screen hero layout replacing the thin button list
- TOP: "PROFESSOR MADRID" wordmark + "¡Vamos!" sub-label with Spanish flag emoji
- VERB GAME card: tall hero card (~240pt), warm gold gradient, animated dice icon, "Practice conjugations fast"
- CHAT TUTOR card: tall hero card (~240pt), deep blue-cyan gradient, chat bubble icon
- Cards: RoundedRectangle cornerRadius 28, subtle inner glow on border, tactile scale press effect
- Bottom: small version label / branding blurb

### [x] Step: MatrixCellView → Glass + Color + Icons
- Corner radius: 10 → 16
- Pending idle: glass morphism (white 9% fill + 1pt border)
- Pending active: electric yellow glow + pulsing scale animation (1.0 → 1.06 breathing)
- Correct: green gradient fill (green 30% → green 15%), ✓ checkmark icon over conjugation
- Missed: red gradient fill, user transcript in small text + correct in bold red
- Timer arc: move inside cell edge, increase lineWidth 4 → 5
- Hint mode: show conjugation in semi-transparent overlay

### [x] Step: GameMatrixView → Cleaner Game Board
- Verb column headers: replace plain Text with "VerbChip" — rounded badge with gold gradient fill, verb in white bold
- Pronoun labels: left column wider (90pt), semibold, white 60% (up from 35%)
- Guidance banner: restyle as full-width "speech bubble" card — rounded, colored border matching active/correct/missed
- Cell height: 52pt → 64pt portrait, 40pt landscape
- ListeningIndicator: replace tiny pill with bottom-anchored full-width "Recording…" banner (pulsing mic icon)
- Review mode header: distinct visual treatment (REVIEW badge instead of toolbar button)

### [x] Step: ResultsView → Celebration Screen
- Background: `GameBackground` (same as game) + `ConfettiView` layer active on perfect score
- Top: large emoji trophy (🏆) for perfect / medal (🥈) for partial — animated entrance
- Score `X / Y`: increase to 80pt black weight, color-coded glow
- "PERFECT! / X MISSED" sub-label with matching color and tracking
- Correct section: green gradient cards, each row has ✓ icon
- Missed section: red gradient cards, each row has ✗ icon + proper verb/pronoun layout
- RETRY MISSED button: stays yellow, increase to 56pt height
- NEW ROUND button: glass variant with icon

### [x] Step: SettingsSheetView → Styled Settings
- Replace `Color.black` with `AppBackground`
- Section header labels with AppColors styling
- Tense picker: slightly taller, labeled sections
- Timer slider: custom thumb color via accent, value badge next to label
- Toggle: styled with larger hit area

### [x] Step: TypewriterIntroView — Atmosphere (optional, if time allows)
- The typewriter mechanic is good — polish the visual frame
- Subtle animated grid/dot overlay on the black background
- Vocabulary word cards revealed with a card-flip or slide animation instead of plain opacity
- "Tap to skip" hint more stylish (bottom of screen, pill shape)
- Bottom vocab section: styled as flashcard chips with border

---

## Status

### [x] Phase 0 — Foundation (Done)
- DesignTheme.swift with AppBackground + AppColors created
- All 6 Chat screens updated: background, font sizes, fullScreenCover modals

### [x] Phase 1 — Expand Design System + Game Screens
- DesignTheme.swift — GameColors, GameBackground, ConfettiView
- ModeSelectorView hero redesign
- MatrixCellView glass morphism overhaul
- GameMatrixView verb badges + bigger cells + better guidance
- ResultsView celebration screen
- SettingsSheetView styled

### [x] Phase 2 — Polish Pass + Chat Input Redesign
- Navigation fix: ← Home in SessionListView
- Font system: monospaced → rounded for Chat screens
- ProfileView redesign with avatar + stats
- Compile fix: ProfileView optional string handling
- Removed redundant LISTENING banner from GameMatrixView
- Increased font sizes in MatrixCellView (20–24pt icons, 18pt conjugation text)
- Fixed nav bar dark mode: toolbarBackground on SessionListView + NewSessionView
- ChatView input bar redesigned: mic circle + text field + big send + Camera/Photos row
- Added CameraPickerView (UIImagePickerController wrapper)
- TypewriterIntroView redesigned: GameBackground, glass quote card, animated vocab tiles, pulsing footer
- New Session navigation bug fixed: callback pattern replaces broken push-then-dismiss

### [x] Phase 3 — Parrot Mode
- FlowLayout.swift: custom SwiftUI Layout for wrapping word chips
- ParrotPhrase.swift: SwiftData @Model with segment paths, messageId, sessionId
- ParrotService.swift: GPT-4o-mini for translation/sentences JSON + Gemini TTS × 7 segments
- LoopingParrotPlayer.swift: AVAudioPlayer chain, N-loop auto-stop, MPRemoteCommandCenter lock screen
- ParrotWordGridView.swift: Duolingo-style word chip grid with matchedGeometryEffect phrase bar
- ParrotPlayerView.swift: generating progress view + loop tracker + play/pause controls
- MessageBubbleView.swift: 🦜 parrot circle button on each assistant message footer
- ChatView.swift: parrot routing (existing phrase → player, new → word grid) + fullScreenCover
- EMOMORENEISAApp.swift: ParrotPhrase added to SwiftData schema
- Info.plist: UIBackgroundModes += audio for lock-screen playback
- PromptBuilder.swift: parrotScriptPrompt() for JSON generation

### [x] Phase 4 — UX Polish + Spanish-First Tutor
- ModeSelectorView: removed subtitle texts from VERB GAME and CHAT TUTOR cards
- SessionListView: removed lastMessagePreview from session rows (show name only)
- NewSessionView: removed instruction text below topic field; custom visible placeholder
- ChatView: GoalEditorSheet changed from .sheet to .fullScreenCover for full-screen editing
- PromptBuilder: system prompt rewritten in Spanish — tutor speaks mostly Spanish, no greetings, direct exercises; opening instruction is now a single-line Spanish command
- LoopingParrotPlayer: added skipToPreviousSegment() and skipToNextSegment() methods
- ParrotPlayerView: player controls updated with ⏮ prev / ⏯ play-pause / ⏭ next / 🔄 restart row

### [x] Phase 6 — ModeSelectorView Dream Animation
- Swapped buttons: Chat Tutor is now top card (with dog); Verb Game is below
- Removed "START PLAYING" and "OPEN CHAT" sub-label capsules from both cards
- Speech bubble right margin now aligned with button right edge (padding(.horizontal, 20))
- DreamParticlesView: 9 images from dogs dreams/without background copied to xcassets as dream_hotdog, dream_pasta, dream_chicken_fried, dream_chicken_roasted, dream_grilled_meat, dream_cheese, dream_books, dream_spanish_book, dream_espanol_books
- DreamParticleItemView: each particle drifts/rotates/fades with easeInOut repeatForever animation, staggered delays, opacity 0→0.52

### [x] Phase 5 — Analytics Architecture (Flow 2)
- Supabase migration applied: profiles v2 columns, analyst_events table, profile_updates audit log
- ProfileModels.swift: WordEntry (SM-2), PhraseEntry (SM-2), ErrorEntry, ExtractionResult, RemoteAnalystEvent, ProfileV2Update
- StudentProfile.swift: ESPProfile expanded with all v2 fields; custom Decodable for graceful fallback; profileDigest computed for tutor prompt injection; LocalStudentProfile updated with Data-backed JSON storage for SwiftData
- PromptBuilder.swift: extractionPrompt() added; topicSystemPrompt() now injects profileDigest into system prompt
- ProfileAnalystService.swift: Task.detached background analyst; calls extraction LLM; applies results to local ESPProfile on MainActor; ships analyst_event + updated profile to Supabase
- SupabaseSyncService.swift: insertAnalystEvent() + updateProfileV2() methods added
- ChatView.swift: ProfileAnalystService.analyzeExchange() fired after every assistant reply (non-blocking)

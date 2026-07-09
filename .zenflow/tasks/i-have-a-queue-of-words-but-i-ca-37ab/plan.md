# Delete Word from Queue

## What was done

Added a delete button to `VocabularyReplayView` (the card detail screen opened when tapping any word in the progress/queue screens).

### [x] Step: Implement delete word feature
- Added a trash icon button in the top-right corner of `VocabularyReplayView`
- Tapping shows a confirmation alert: "Remove Word?" with the word name and a warning that all progress will be lost
- On confirm: stops audio playback (looping player + TTS), calls `MemoryCardService.delete()` which emits a `.deleted` Supabase sync event and removes the card from SwiftData, refreshes `MemoryCardNotificationService` with the updated due count so the daily notification is correctly updated/canceled, then dismisses the card view
- All `@Query`-driven lists (Hub, Stats, Vocabulary) auto-refresh via SwiftData observation — no extra wiring needed

### [x] Step: Upload to TestFlight
- Built and uploaded **build 31** to TestFlight via `fastlane beta`
- Upload succeeded, build processed successfully

### [x] Step: Bug fixes (build 32)
- Fixed dog phrases continuing to play when switching from Explore → My Chats (added `.onChange(of: showSessionList)` in `NewSessionView` to stop audio/typewriter tasks)
- Fixed due words being split across multiple sessions (`LoroMemorizeHubView` timer now ticks `now` every 30s so newly-due cards are included immediately)

### [x] Step: Back button consistency
- Added shared `BackButton` view in `DesignTheme.swift` — a 36pt circle with `.ultraThinMaterial` fill and a white `chevron.left` icon
- Replaced all inconsistent back/dismiss controls across the app:
  - `SessionListView`: toolbar "Home" text → `BackButton`
  - `ChatView`: toolbar "Back" text → `BackButton`
  - `GoalEditorSheet` (in `ChatView`): toolbar "Cancel" text → `BackButton`
  - `AnnotationCanvasView`: capsule "Back" overlay → `BackButton`
  - `ParrotPlayerView`: HStack "Back to Chat" → `BackButton`
  - `SRSPlayerView`: HStack "Done" → `BackButton`
  - `LoroMemorizeHubView` header: HStack "Home" → `BackButton`
  - `VocabularyReplayView`: removed yellow "Done" pill; added `BackButton` at top-left (stops audio + dismisses); trash icon remains at top-right
  - `NewSessionView.modeSelectionFullScreen`: "Cancel" capsule overlay → `BackButton`
  - `ParrotWordGridView`: toolbar "Cancel" text → `BackButton`
  - `SlotMachineView`: "Back" HStack → `BackButton` (preserves existing `engine.newRound()` action)

# Fix Verano Prado recording

### [x] Step: Replace SpeechService with AudioRecorder in GameEngine

Replaced Apple's `SFSpeechRecognizer` (`SpeechService`) with `AudioRecorder` in `GameEngine`.
`AudioRecorder` records the full cell window to an `.m4a` file then sends it to `gpt-4o-transcribe`
via the proxy — the advanced server-side model that correctly handles Spanish verb endings.

**Key changes in `GameEngine.swift`:**
- `SpeechService` → `AudioRecorder` (uses OpenAI gpt-4o-transcribe, not on-device STT)
- Removed `PronounPlayer.shared.play()` call from `startCellTimer()` — pronoun audio was the
  source of the `AVAudioSession` conflict that broke recording
- Recording starts **immediately** when the cell timer starts (no 0.6 s delay)
- When the timer expires, the recording is stopped and sent to the proxy; `isPostProcessing`
  stays true during the network round-trip (shows "PROCESSING…" in UI)
- `postProcessTimer` removed — transcription latency replaces the old blind post-window
- `retryCell(at:)` now records for 5 seconds then transcribes via proxy (same model)
- All stale `sttHints` / `listeningGeneration` streaming logic removed (not needed for file-based STT)

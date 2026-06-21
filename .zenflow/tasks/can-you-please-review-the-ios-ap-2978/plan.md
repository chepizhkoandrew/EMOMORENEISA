# Spanish Chat Tutor — Implementation Plan

Spec: `.zenflow/tasks/can-you-please-review-the-ios-ap-2978/chatbot-spec.md`

---

### [x] Step: Review & Specification
- Reviewed existing iOS codebase (GameEngine, SpeechService, GeminiService, all views)
- Authored `chatbot-spec.md` with full architecture, data models, UI wireframes, and LLM prompts
- All key decisions confirmed by user (Supabase, Google Sign-In, SwiftData, AVSpeechSynthesizer, iOS 17+)

### [ ] Step 1: Manual Setup (user action required before coding)
- Create new Supabase project at supabase.com (separate from Melto)
- Enable Google OAuth in Supabase (Settings → Auth → Providers → Google)
  - Use the same Google OAuth Client ID as VeranoPrado
  - Add Supabase callback URL to Google Cloud Console OAuth allowed redirects
- Run the SQL migration from spec §5.1 in the Supabase SQL editor
- Create Supabase Storage buckets: `esp-audio` and `esp-images` (both private)
- Copy `SUPABASE_URL` and `SUPABASE_ANON_KEY` to `Secrets.xcconfig`
- From Google Cloud Console, download `GoogleService-Info.plist`
- In Xcode: Add SPM packages:
  - `https://github.com/supabase/supabase-swift` (exact version: latest stable)
  - `https://github.com/google/GoogleSignIn-iOS` (exact version: latest stable)
- Add `GoogleService-Info.plist` to the Xcode target
- Add URL scheme for Google Sign-In to `Info.plist` (from `GoogleService-Info.plist` REVERSED_CLIENT_ID)

### [x] Step 2: Foundation — Auth, Navigation & Student Profile
- `SupabaseClient.swift` — singleton wrapping `SupabaseClient` with URL/key from bundle
- `AuthState.swift` — `@Observable` class holding current user + profile; silent session restore on launch
- `AuthService.swift` — `signInWithGoogle()`, `signOut()`, Supabase JWT exchange
- `SignInView.swift` — "¡Hola!" screen with Google Sign-In button (dark theme matching app)
- `StudentProfile.swift` — SwiftData `@Model` (id, displayName, level, nativeLanguage, focusTopics, currentStudyTopic, learningNotes)
- `ProfileService.swift` — create profile on first sign-in; read/update from `esp_profiles`
- `ProfileView.swift` — display name, level picker, focus topics text field, learning notes (read-only), sign out
- `ModeSelectorView.swift` — replace tap-to-continue in `TypewriterIntroView`: two cards: VERB GAME + CHAT TUTOR
- Modify `HomeView.swift` to show `ModeSelectorView` after intro animation completes
- Wire `EMOMORENEISAApp.swift`: inject `AuthState` into environment; add SwiftData `ModelContainer`

### [x] Step 3: Text Chat — Sessions & Messages
- `ChatSession.swift` — SwiftData `@Model`
- `ChatMessage.swift` — SwiftData `@Model`
- `SessionService.swift` — create/load/list sessions; sync to `esp_sessions`
- `SupabaseSyncService.swift` — write messages to `esp_messages`; retry queue for offline
- `SessionListView.swift` — list of past sessions with mode badge, last message preview, relative timestamp; "+" button
- `NewSessionView.swift` — mode selector (Topic / Visual) + topic text field for Topic Mode; "Start Session" launches chat
- `ChatView.swift` — `ScrollView` of message bubbles; auto-scroll to bottom on new message; input bar at bottom
- `MessageBubbleView.swift` — text bubble (user: right/gold, assistant: left/gray); long-press menu on assistant bubbles ("Reply in thread")
- `InputBarView.swift` — `TextField` + send button; mic button (placeholder for Phase 3); camera button (placeholder for Phase 4)
- `ChatGeminiService.swift` — `sendMessage(history:systemPrompt:userMessage:)` → returns `String`
- `PromptBuilder.swift` — builds Topic Mode and Visual Mode system prompts from `StudentProfile`
- End-to-end flow: user types → Gemini called with Topic Mode prompt → assistant text bubble shown

### [ ] Step 4: Voice — Recording, Playback & TTS
- `AudioRecorder.swift` — `AVAudioRecorder` to `.m4a`; level metering array for waveform; hold-to-record / release-to-send / swipe-up-to-cancel
- Recording overlay view — fullscreen dark overlay with live waveform bars (`Canvas`), REC timer, instruction labels
- After recording: `SFSpeechRecognizer` transcribes → Gemini enhancement call → message sent with `rawTranscript` + `textContent`
- `TTSService.swift` — `AVSpeechSynthesizer` speaks Gemini response; tap `AVAudioEngine` output to capture `.m4a`; stores file to `Documents/esp-audio/{sessionId}/{messageId}.m4a`
- `AudioPlayer.swift` — `AVAudioPlayer` wrapper with `@Published` `isPlaying`, `progress`, `duration`
- `AudioBubbleView.swift` — play/pause button + scrubber bar + duration label + collapsible transcript text
- Replace `InputBarView` mic button with hold-gesture that triggers `AudioRecorder`
- Async upload audio `.m4a` to Supabase Storage `esp-audio` bucket; store path in `esp_messages.audio_storage_path`
- Update `Info.plist`: `NSMicrophoneUsageDescription` (already present; update text for chat context)

### [ ] Step 5: Visual Mode — Photos & Gemini Vision
- `PhotoPickerButton` in `InputBarView` — opens `PhotosPicker` (SwiftUI) for 1–4 images
- `ImageBubbleView.swift` — grid thumbnail display for sent images
- Gemini multimodal call in `ChatGeminiService` — encode images as base64 inline data parts alongside text prompt; use Visual Mode system prompt from `PromptBuilder`
- `NewSessionView` Visual Mode path: selecting Visual Mode skips topic field; first user action is sending photo(s)
- Session list shows thumbnail of first image as session card cover
- Update `Info.plist`: `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`
- Async upload images to Supabase Storage `esp-images` bucket

### [ ] Step 6: Threads
- Add `threadParentId` relationship to `ChatMessage` SwiftData model (already designed in spec)
- `ThreadSheetView.swift` — `sheet` sliding up from bottom; shows pinned parent message (grayed) + thread messages; own `InputBarView`; same voice + text input as main chat
- Long-press assistant bubble context menu: "↩ Reply in thread" → opens `ThreadSheetView` with that message as parent
- LLM context for thread calls: system prompt + parent message + thread messages only (not full session history)
- Supabase sync: `thread_id` column on `esp_messages` populated for thread replies
- Thread reply count badge on parent bubble in main chat (e.g. "3 replies →")

### [ ] Step 7: Polish & Session Intelligence
- Session summary: on `ChatView` dismiss / session end → background Gemini call summarizing what was practiced + weaknesses → appended to `esp_profiles.learning_notes`
- Streak tracking: `streakDays` computed from `esp_sessions.created_at`; shown on `ProfileView`
- Stats on `ProfileView`: total sessions, total messages, current streak
- Empty states: `SessionListView` empty state with illustration + "Start your first lesson" CTA
- Loading states: shimmer placeholders while sessions load; spinner while Gemini responds
- Error handling: network error banners; retry buttons; graceful offline mode (local data always visible)
- Offline indicator in `ChatView` when no internet (LLM unavailable)
- `Info.plist` entries audit: ensure all privacy strings are accurate and user-facing friendly

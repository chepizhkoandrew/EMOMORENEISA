# Spanish Chatbot — Technical Specification (Final)

---

## 1. Feature Overview

A conversational Spanish tutor built as a **new tab** inside the existing iOS app. Users exchange text, voice, and photo messages with an AI tutor. Messages are asynchronous (WhatsApp/iMessage style). The tutor has two conversation modes: Topic Mode and Visual Mode.

---

## 2. Architecture Decision Record

| Decision | Choice | Reason |
|---|---|---|
| Backend | **New Supabase project** | Isolated from Melto; $10/mo is worth the clean separation |
| Auth | **Google Sign-In** | Same Google OAuth client as VeranoPrado project |
| Local persistence | **SwiftData** (iOS 17+) | Supported target; clean Swift-native ORM |
| TTS | **AVSpeechSynthesizer** | Free, offline, supports `es-ES` + `en-US` |
| STT | **SFSpeechRecognizer** (already in app) | Already integrated; Gemini post-processes transcript |
| LLM | **Gemini 2.0 Flash** (already integrated) | Existing API key; supports text + images |
| Entry point | **New "CHAT" tab** on the mode-selection home screen | Separate flow, not mixed with verb game |
| iOS minimum | **iOS 17** | Required for SwiftData |

---

## 3. App Navigation & Entry Point

### 3.1 Current Home Screen (modified)
The current `TypewriterIntroView` becomes a **mode selector** screen. After the typewriter animation completes and the user taps, instead of going directly to the verb game, they see two large buttons:

```
┌─────────────────────────────────────────┐
│                                         │
│   ╔═══════════════════════════════╗     │
│   ║                               ║     │
│   ║   🎰  VERB GAME               ║     │
│   ║   Practice conjugations       ║     │
│   ║                               ║     │
│   ╚═══════════════════════════════╝     │
│                                         │
│   ╔═══════════════════════════════╗     │
│   ║                               ║     │
│   ║   💬  CHAT TUTOR              ║     │
│   ║   AI-powered Spanish lessons  ║     │
│   ║                               ║     │
│   ╚═══════════════════════════════╝     │
│                                         │
└─────────────────────────────────────────┘
```

- VERB GAME → existing flow (unchanged)
- CHAT TUTOR → authentication check → if logged in: session list; if not: Google Sign-In screen

---

## 4. Authentication Flow

### 4.1 Google Sign-In
- Uses **GoogleSignIn iOS SDK** (`pod 'GoogleSignIn'` or SPM)
- Same OAuth 2.0 client ID as VeranoPrado project
- After successful Google auth, exchange token with Supabase's Google OAuth endpoint → get Supabase JWT
- JWT stored in Keychain via Supabase Swift client
- Silent refresh on app launch

### 4.2 Sign-In Screen UI
```
┌─────────────────────────────────────────┐
│                                         │
│        ¡Hola!                           │
│        Sign in to save your progress    │
│        and continue your Spanish        │
│        journey.                         │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │  G  Continue with Google        │   │
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

### 4.3 Student Profile
Created on first sign-in. Editable from settings.

Fields:
- `display_name` (String)
- `level` — enum: `beginner | intermediate | advanced`
- `native_language` — default "English"
- `focus_topics` — String array (e.g. ["present tense", "travel vocabulary"])
- `current_study_topic` — String? (the active focus, set per-session or globally)
- `learning_notes` — free text (auto-updated by AI after sessions summarizing key weaknesses)
- `created_at`, `updated_at`

The student profile is **injected into every LLM system prompt** so the tutor always knows who it's talking to.

---

## 5. Data Models

### 5.1 Supabase Schema (prefix: `esp_`)

```sql
-- Student profile
CREATE TABLE esp_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  level TEXT DEFAULT 'beginner' CHECK (level IN ('beginner','intermediate','advanced')),
  native_language TEXT DEFAULT 'English',
  focus_topics TEXT[] DEFAULT '{}',
  current_study_topic TEXT,
  learning_notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Chat sessions
CREATE TABLE esp_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL CHECK (mode IN ('topic','visual')),
  title TEXT,
  topic TEXT,          -- for topic mode: what we're focusing on
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  message_count INT DEFAULT 0
);

-- Messages (root thread + sub-threads)
CREATE TABLE esp_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES esp_sessions(id) ON DELETE CASCADE,
  thread_id UUID REFERENCES esp_messages(id) ON DELETE CASCADE,  -- NULL = root
  sender TEXT NOT NULL CHECK (sender IN ('user','assistant')),
  type TEXT NOT NULL CHECK (type IN ('text','audio','image','mixed')),
  text_content TEXT,           -- transcript for audio; caption for image
  raw_transcript TEXT,         -- pre-enhancement STT output
  audio_storage_path TEXT,     -- Supabase Storage path: sessions/{session_id}/{message_id}.m4a
  image_storage_paths TEXT[],  -- Supabase Storage paths for images
  is_enhanced BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Row Level Security
ALTER TABLE esp_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE esp_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE esp_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users own their profile" ON esp_profiles
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "Users own their sessions" ON esp_sessions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users own their messages" ON esp_messages
  FOR ALL USING (
    session_id IN (SELECT id FROM esp_sessions WHERE user_id = auth.uid())
  );
```

### 5.2 Supabase Storage
- Bucket: `esp-audio` (private, authenticated only)
- Path pattern: `{user_id}/{session_id}/{message_id}.m4a`
- Bucket: `esp-images` (private)
- Path pattern: `{user_id}/{session_id}/{message_id}/{index}.jpg`

### 5.3 SwiftData Local Models

```swift
@Model class ChatSession {
    var id: UUID
    var mode: String          // "topic" | "visual"
    var title: String?
    var topic: String?
    var createdAt: Date
    var updatedAt: Date
    var isSyncedToBackend: Bool
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]
}

@Model class ChatMessage {
    var id: UUID
    var sessionId: UUID
    var threadParentId: UUID?   // nil = root message
    var sender: String          // "user" | "assistant"
    var type: String            // "text" | "audio" | "image" | "mixed"
    var textContent: String?
    var rawTranscript: String?
    var audioLocalPath: String? // Documents/esp-audio/{session_id}/{message_id}.m4a
    var imageLocalPaths: [String]
    var isEnhanced: Bool
    var createdAt: Date
    var isSyncedToBackend: Bool
}
```

---

## 6. UI Design

### 6.1 Session List Screen
```
┌─────────────────────────────────────────┐
│  ← CHAT TUTOR                  [+ New]  │
├─────────────────────────────────────────┤
│  ┌───────────────────────────────────┐  │
│  │ 📚 TOPIC MODE                     │  │
│  │ Ser vs Estar                      │  │
│  │ "Can you give me more examples…"  │  │
│  │                        2h ago  ›  │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │ 📸 VISUAL MODE                    │  │
│  │ Street scene - Barcelona          │  │
│  │ "¿Qué ves en la imagen?"          │  │
│  │                     Yesterday  ›  │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ 📚 TOPIC MODE                     │  │
│  │ Travel vocabulary                 │  │
│  │ "The word for airport is…"        │  │
│  │                    3 days ago  ›  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 6.2 New Session Modal
```
┌─────────────────────────────────────────┐
│  New Session                      [✕]   │
├─────────────────────────────────────────┤
│                                         │
│  What do you want to practice?          │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ 📚  TOPIC MODE                    │  │
│  │     Focus on a grammar rule,      │  │
│  │     verb, or vocabulary topic     │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ 📸  VISUAL MODE                   │  │
│  │     Send a photo and discuss      │  │
│  │     what you see in Spanish       │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ── Topic Mode Setup ───────────────    │
│  What should we focus on today?         │
│  ┌─────────────────────────────────┐    │
│  │ e.g. "subjunctive mood"         │    │
│  └─────────────────────────────────┘    │
│                                         │
│  [  START SESSION  ]                    │
└─────────────────────────────────────────┘
```

### 6.3 Chat Screen (Session)
```
┌─────────────────────────────────────────┐
│  ← Ser vs Estar          [👤 Profile]   │
│     📚 Topic · Intermediate             │
├─────────────────────────────────────────┤
│                                         │
│        ┌──────────────────────────┐     │
│        │ ¡Hola! Hoy vamos a       │     │
│        │ practicar ser vs estar.  │     │
│        │ ¿Estás listo?            │     │
│        │ ▶ 0:04  ══════○──────    │     │
│        │ Tap to read transcript   │     │
│        │              [↩ Reply]   │     │
│        └──────────────────────────┘     │
│                                         │
│  ┌────────────────────────────┐         │
│  │ Sí, estoy listo            │         │
│  │ ▶ 0:02  ══○────────────    │         │
│  └────────────────────────────┘         │
│                                         │
│        ┌──────────────────────────┐     │
│        │ ¡Perfecto! Let's start   │     │
│        │ with a simple sentence…  │     │
│        │ ▶ 0:06  ═══════○───────  │     │
│        │              [↩ Reply]   │     │
│        └──────────────────────────┘     │
│                                         │
├─────────────────────────────────────────┤
│ ┌────────────────────────┐ [🎤] [📷] [➤]│
│ │  Type a message...     │              │
│ └────────────────────────┘              │
└─────────────────────────────────────────┘
```

**Message bubble anatomy:**
- Assistant bubbles: left-aligned, dark gray background
- User bubbles: right-aligned, dark yellow/gold accent
- Audio bubble: play/pause + progress bar + duration + collapsed transcript
- Tap transcript area → expands to show full text
- Long-press assistant bubble → "↩ Reply in thread" + "▶ Play" actions

### 6.4 Voice Recording Overlay
```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│   ●  REC  0:03                          │
│                                         │
│   ▂▄▆█▆▄▂▄▆▄▂▄▆▄▂▄▆▄▂▂▄▄▆▆▄▂▂         │
│        (live waveform)                  │
│                                         │
│   Release to send                       │
│   Swipe up to cancel                    │
│                                         │
│              ●                          │
│         (hold button)                   │
│                                         │
└─────────────────────────────────────────┘
```

### 6.5 Thread Sheet (Slack-style)
```
┌─────────────────────────────────────────┐
│  Thread                           [✕]   │
├─────────────────────────────────────────┤
│  ── Parent message ─────────────────    │
│  ┌──────────────────────────────────┐   │
│  │ ¡Perfecto! Let's start with a    │   │
│  │ simple sentence…                 │   │
│  │ ▶ 0:06  (grayed / non-clickable) │   │
│  └──────────────────────────────────┘   │
│  ─────────────────────────────────────  │
│                                         │
│  ┌──────────────────────────────┐       │
│  │ Sorry, I don't understand    │       │
│  └──────────────────────────────┘       │
│                                         │
│        ┌────────────────────────────┐   │
│        │ No problem! Let me explain │   │
│        │ it differently…            │   │
│        │ ▶ 0:08                     │   │
│        └────────────────────────────┘   │
│                                         │
├─────────────────────────────────────────┤
│ ┌────────────────────────┐ [🎤] [➤]     │
│ │  Reply in thread...    │              │
│ └────────────────────────┘              │
└─────────────────────────────────────────┘
```

### 6.6 Student Profile Screen
```
┌─────────────────────────────────────────┐
│  ← My Profile                           │
├─────────────────────────────────────────┤
│  👤  Andrii                             │
│      andrii@gmail.com                   │
│                                         │
│  ── Learning Level ─────────────────    │
│  ○ Beginner  ● Intermediate  ○ Advanced  │
│                                         │
│  ── Current Focus ──────────────────    │
│  ┌─────────────────────────────────┐    │
│  │ Subjunctive mood, travel vocab  │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ── What I'm Working On ────────────    │
│  ┌─────────────────────────────────┐    │
│  │ [auto-updated by AI after each  │    │
│  │  session — key weaknesses,      │    │
│  │  mastered topics, etc.]         │    │
│  └─────────────────────────────────┘    │
│  [Edit]                                 │
│                                         │
│  ── Stats ──────────────────────────    │
│  12 sessions  ·  47 messages  ·  4d 🔥  │
│                                         │
│                  [Sign Out]             │
└─────────────────────────────────────────┘
```

---

## 7. LLM Integration

### 7.1 Context Assembly per Request
```
[System prompt]
  ↓
[Student profile snapshot]
  ↓
[Last 20 messages from active thread (transcripts only)]
  ↓
[User's new message]
```

### 7.2 System Prompts

**Topic Mode:**
```
You are a warm, patient, and encouraging private Spanish tutor.
Student profile:
  - Name: {name}
  - Level: {level}
  - Native language: {native_language}
  - Current focus: {current_study_topic}
  - Known weaknesses: {learning_notes}

Today's topic: {session_topic}

Rules:
- Ask ONE question at a time. Wait for the student's response.
- If they struggle, offer a word or phrase to repeat first, then ask again.
- Correct mistakes gently but clearly, in one short sentence.
- Praise genuine effort, but do not over-praise wrong answers.
- Explain grammar rules in {native_language}, practice in Spanish.
- ALWAYS end your message with a clear question or prompt for the student.
- Keep responses SHORT: 2–4 sentences maximum.
- Use the student's name occasionally to personalize.
```

**Visual Mode:**
```
You are a Spanish tutor helping a student practice through real-world photos.
Student profile:
  - Name: {name}
  - Level: {level}
  - Current focus: {current_study_topic}

The student has shared a photo. Analyze what you see and start a natural 
Spanish conversation about it.

Rules:
- Identify 2-3 interesting objects or actions in the image.
- Introduce one Spanish word or phrase tied to the image.
- Ask the student to describe something they see in Spanish.
- Be encouraging and curious, like a tutor on a field trip.
- Keep responses SHORT: 2–4 sentences.
```

### 7.3 Transcript Enhancement Call
After STT delivers raw text, a fast Gemini call cleans it up before sending to the main LLM:
```
Conversation context (last 3 messages): {context}
Raw speech-to-text: "{raw}"
Fix any speech-to-text errors for Spanish words, accent marks, 
or common homophones (b/v, c/s/z). Return ONLY the corrected text.
```

### 7.4 Session Summary (after session ends)
When a session closes, a background Gemini call generates a short summary of what was practiced and any key weaknesses observed. This is appended to `esp_profiles.learning_notes`.

---

## 8. Audio Pipeline

### 8.1 Recording
1. User holds mic button → `AVAudioRecorder` starts capturing to temp file
2. Visual: waveform overlay (using `AVAudioPCMBuffer` level metering)
3. Release → recording stops → file saved as `.m4a`
4. `SFSpeechRecognizer` transcribes → transcript shown to user briefly
5. Gemini enhancement call → corrected transcript
6. Message sent with both `rawTranscript` and enhanced `textContent`

### 8.2 Playback (user messages)
- `AVAudioPlayer` plays from local `.m4a` file
- Progress bar updates via `Timer`

### 8.3 TTS (assistant messages)
1. Gemini response text received
2. `AVSpeechSynthesizer` synthesizes to `AVSpeechUtterance`
3. Audio captured via `AVAudioEngine` tap → saved to `.m4a`
4. Displayed as audio bubble with play button
5. Transcript available by tap

TTS voices:
- Spanish: `AVSpeechSynthesisVoice(language: "es-ES")` or `"es-MX"`
- English: `AVSpeechSynthesisVoice(language: "en-US")`

### 8.4 Audio File Storage
- Local: `Documents/esp-audio/{session_id}/{message_id}.m4a`
- Remote: Supabase Storage bucket `esp-audio` (async upload after save)

---

## 9. New File Structure

```
EMOMORENEISA/
├── App/
│   └── EMOMORENEISAApp.swift       (modified: add ChatModule)
├── Chat/                           ← NEW
│   ├── Auth/
│   │   ├── AuthService.swift       (Google Sign-In + Supabase)
│   │   ├── SignInView.swift
│   │   └── AuthState.swift
│   ├── Profile/
│   │   ├── StudentProfile.swift    (model + SwiftData)
│   │   ├── ProfileView.swift
│   │   └── ProfileService.swift
│   ├── Sessions/
│   │   ├── ChatSession.swift       (SwiftData model)
│   │   ├── SessionListView.swift
│   │   ├── NewSessionView.swift
│   │   └── SessionService.swift
│   ├── Messages/
│   │   ├── ChatMessage.swift       (SwiftData model)
│   │   ├── ChatView.swift          (main chat screen)
│   │   ├── MessageBubbleView.swift
│   │   ├── AudioBubbleView.swift
│   │   ├── ImageBubbleView.swift
│   │   ├── ThreadSheetView.swift
│   │   └── InputBarView.swift
│   ├── Audio/
│   │   ├── AudioRecorder.swift
│   │   ├── AudioPlayer.swift
│   │   └── TTSService.swift        (AVSpeechSynthesizer → .m4a)
│   ├── LLM/
│   │   ├── ChatGeminiService.swift (chat-specific Gemini calls)
│   │   └── PromptBuilder.swift
│   └── Supabase/
│       ├── SupabaseClient.swift
│       └── SupabaseSyncService.swift
├── Home/                           ← MODIFIED
│   └── ModeSelectorView.swift      (new: verb game vs chat tutor)
└── (existing files unchanged)
```

---

## 10. Implementation Phases

### Phase 1 — Foundation (Auth + Navigation + Student Profile)
- Google Sign-In SDK integration
- Supabase project setup + SQL migration
- `AuthService`, `AuthState`
- `ModeSelectorView` (replace/wrap current intro tap destination)
- `SignInView`
- Student profile creation on first sign-in
- `ProfileView` (read + edit)
- SwiftData container setup

### Phase 2 — Text Chat (Sessions + Messages)
- `SessionListView` + `NewSessionView`
- `ChatView` with text-only messages
- Gemini integration with Topic Mode system prompt (injecting student profile)
- `SessionService` + `SupabaseSyncService`
- SwiftData local persistence
- Supabase sync (messages + sessions)

### Phase 3 — Voice (Recording + Playback + TTS)
- `AudioRecorder` (hold-to-record, waveform overlay)
- `AVAudioPlayer` for user audio playback
- `TTSService` (synthesize Gemini response → `.m4a`)
- `AudioBubbleView` (play/pause bar + transcript toggle)
- STT → Gemini enhancement pipeline
- Supabase Storage upload for audio files

### Phase 4 — Visual Mode
- Photo picker + camera integration
- `ImageBubbleView`
- Gemini Vision multimodal call (base64 images in request)
- Session mode = "visual" flow

### Phase 5 — Threads
- Thread data model (SwiftData + Supabase)
- `ThreadSheetView`
- "Reply in thread" long-press action on assistant bubbles
- Thread-scoped LLM context

### Phase 6 — Polish
- Session summary generation (background Gemini call → `learning_notes`)
- Streak tracking
- Profile stats
- Error states, loading states, offline mode UX
- `Info.plist` additions (camera, photo library permissions)

---

## 11. Dependencies to Add (SPM)

```
https://github.com/supabase/supabase-swift  (Supabase)
https://github.com/google/GoogleSignIn-iOS  (Google Sign-In)
```

Existing dependencies already in project:
- `AVFoundation`, `Speech` (already used)
- `Gemini` (custom GeminiService, already wired)

---

## 12. Supabase Setup Checklist

1. Create new Supabase project at supabase.com
2. Enable Google OAuth provider (Settings → Auth → Providers → Google)
   - Use same Google OAuth client ID as VeranoPrado
3. Run SQL migration (§5.1)
4. Create storage buckets: `esp-audio`, `esp-images` (both private)
5. Copy `SUPABASE_URL` and `SUPABASE_ANON_KEY` → add to `Secrets.xcconfig`
6. Add `Supabase` and `GoogleSignIn` via Swift Package Manager
7. Add `GoogleService-Info.plist` to Xcode project (from Google Cloud Console)

# Professor Madrid — Data Models

Reference for all data structures across Supabase, iOS Swift models, and inter-service JSON contracts.

---

## Supabase Tables

### `profiles` — Student Profile

```sql
id                UUID        PK, references auth.users
display_name      TEXT
level             TEXT        'beginner' | 'intermediate' | 'advanced'
native_language   TEXT        default 'English'
focus_topics      TEXT[]
current_study_topic TEXT
learning_notes    TEXT        free prose, tutor-accumulated notes

-- v2 additions (migration 20260617000000)
word_bank         JSONB       []  array of WordEntry
phrase_bank       JSONB       []  array of PhraseEntry
error_log         JSONB       []  array of ErrorEntry (last 50)
session_summaries JSONB       []  array of SessionSummary (last 10)
weak_areas        TEXT[]      e.g. ['ser vs estar', 'preterite irregular']
mastered_areas    TEXT[]      e.g. ['present tense regular', 'numbers 1-100']
life_notes        TEXT        free prose personal context
hobbies           TEXT[]      e.g. ['running', 'tech', 'travel']
why_learning      TEXT        e.g. 'want to live in Barcelona in 2 years'
practice_style    TEXT        e.g. 'short sessions on the go, commute/running'
target_level      TEXT        e.g. 'B2'
exercise_history  TEXT[]      last 10 exercise types used (avoid repetition)

session_count     INT
message_count     INT
created_at        TIMESTAMPTZ
updated_at        TIMESTAMPTZ
```

---

### `sessions` — Chat Sessions

```sql
id                UUID        PK
user_id           UUID        references auth.users
mode              TEXT        'topic' | 'visual'
title             TEXT
topic             TEXT
session_goal      TEXT        current focus, updated dynamically during session
message_count     INT
last_message_at   TIMESTAMPTZ
created_at        TIMESTAMPTZ
updated_at        TIMESTAMPTZ
```

---

### `messages` — Individual Messages

```sql
id                UUID        PK
session_id        UUID        references sessions
thread_parent_id  UUID?       references messages (for thread replies)
sender            TEXT        'user' | 'assistant'
type              TEXT        'text' | 'audio' | 'image' | 'mixed'
text_content      TEXT?
raw_transcript    TEXT?       pre-enhancement speech-to-text
audio_storage_path TEXT?
image_storage_paths TEXT[]
is_enhanced       BOOLEAN
thread_reply_count INT
created_at        TIMESTAMPTZ
```

---

### `analyst_events` — Per-Turn Analysis Log

```sql
id                UUID        PK
user_id           UUID        references auth.users
session_id        UUID        references sessions
message_id        UUID        ID of the assistant message this analyzes
user_message      TEXT?       the student's turn that prompted the reply
tutor_reply       TEXT        the assistant message content
extracted         JSONB       ExtractionResult (see below)

-- computed columns (no JSON parsing needed for queries)
words_count       INT         length of extracted.words_introduced
phrases_count     INT         length of extracted.phrases_introduced
errors_count      INT         length of extracted.errors_corrected
has_life_fact     BOOLEAN     extracted.student_life_fact is not null

processed_at      TIMESTAMPTZ
analyst_version   TEXT        'v1'
```

---

### `profile_updates` — Audit Log

```sql
id                UUID        PK
user_id           UUID        references auth.users
source            TEXT        'ios_analyst' | 'nightly_job' | 'session_summary' | 'manual'
field_changed     TEXT        e.g. 'word_bank', 'weak_areas', 'life_notes'
previous_value    JSONB
new_value         JSONB
trigger_event_id  UUID?       references analyst_events
created_at        TIMESTAMPTZ
```

---

## JSON Sub-Object Schemas

### WordEntry (inside `profiles.word_bank`)

```json
{
  "word": "poder",
  "translation": "to be able to / can",
  "context": "¿Puedes repetir eso?",
  "first_seen": "2024-03-10T10:22:00Z",
  "last_reviewed": "2024-03-13T08:00:00Z",
  "next_due": "2024-03-16T00:00:00Z",
  "interval_days": 3,
  "ease_factor": 2.5,
  "correct_streak": 2,
  "total_reviews": 4,
  "incorrect_count": 1
}
```

**SM-2 interval update rules:**
- Correct answer: `interval = round(interval * ease_factor)`, `ease_factor = max(1.3, ease_factor + 0.1)`
- Incorrect answer: `interval = 1`, `ease_factor = max(1.3, ease_factor - 0.2)`
- New word: `interval = 1`, `ease_factor = 2.5`

---

### PhraseEntry (inside `profiles.phrase_bank`)

```json
{
  "phrase": "no puedo esperar más",
  "meaning": "I can't wait anymore",
  "context": "Said in context of anticipation",
  "first_seen": "2024-03-10T10:22:00Z",
  "next_due": "2024-03-13T00:00:00Z",
  "interval_days": 3,
  "ease_factor": 2.5,
  "correct_streak": 1,
  "total_reviews": 1,
  "incorrect_count": 0
}
```

---

### ErrorEntry (inside `profiles.error_log`)

```json
{
  "error": "yo soy cansado",
  "correction": "yo estoy cansado",
  "rule": "estar for temporary states, ser for permanent characteristics",
  "session_id": "uuid",
  "occurred_at": "2024-03-10T10:22:00Z",
  "recurrence_count": 2
}
```

---

### SessionSummary (inside `profiles.session_summaries`)

```json
{
  "session_id": "uuid",
  "date": "2024-03-10T10:22:00Z",
  "focus": "preterite tense irregular verbs",
  "summary": "Drilled 'ir', 'ser', 'hacer' in preterite. Student confused 'fui' with imperfect 'iba' twice. Strong recall on 'hice' and 'tuve'. Recommend more preterite vs imperfect contrast next session.",
  "words_introduced": 4,
  "errors_corrected": 2
}
```

---

## ExtractionResult — Analyst Prompt Output Contract

This is the JSON the `ProfileAnalystService` requests from OpenAI and parses.
The prompt must instruct the model to return ONLY this JSON, no prose.

```json
{
  "words_introduced": [
    {
      "word": "poder",
      "translation": "to be able to / can",
      "context": "¿Puedes repetir eso?"
    }
  ],
  "phrases_introduced": [
    {
      "phrase": "a lo mejor",
      "meaning": "maybe / perhaps"
    }
  ],
  "errors_corrected": [
    {
      "error": "yo soy cansado",
      "correction": "yo estoy cansado",
      "rule": "estar for temporary states"
    }
  ],
  "topics_covered": ["preterite tense", "irregular verbs"],
  "student_life_fact": "mentioned commuting by metro",
  "exercise_type_delivered": "conjugation_drill",
  "estimated_difficulty": 2
}
```

**Field notes:**
- `student_life_fact`: null if nothing personal was mentioned. Short string if something was.
- `exercise_type_delivered`: one of `conjugation_drill`, `gap_fill`, `error_correction`, `back_translation`, `recall`, `generative_use`, `minimal_pairs`, `chunk_memorize`, `free_conversation`
- `estimated_difficulty`: 1 (very easy) to 5 (very hard), from the student's apparent experience

---

## iOS Swift Models

### ESPProfile (Codable, Identifiable)

Current model extended with v2 fields. Full definition in `Chat/Profile/StudentProfile.swift`.

```swift
struct ESPProfile: Codable, Identifiable {
    // v1 (existing)
    let id: UUID
    var displayName: String?
    var level: String
    var nativeLanguage: String
    var focusTopics: [String]
    var currentStudyTopic: String?
    var learningNotes: String
    var sessionCount: Int
    var messageCount: Int
    var createdAt: Date
    var updatedAt: Date

    // v2 (new)
    var wordBank: [WordEntry]
    var phraseBank: [PhraseEntry]
    var errorLog: [ErrorEntry]
    var sessionSummaries: [SessionSummary]
    var weakAreas: [String]
    var masteredAreas: [String]
    var lifeNotes: String
    var hobbies: [String]
    var whyLearning: String?
    var practiceStyle: String?
    var targetLevel: String?
    var exerciseHistory: [String]
}
```

### WordEntry (Codable)

```swift
struct WordEntry: Codable, Identifiable {
    var id: UUID
    var word: String
    var translation: String
    var context: String?
    var firstSeen: Date
    var lastReviewed: Date?
    var nextDue: Date
    var intervalDays: Int
    var easeFactor: Double
    var correctStreak: Int
    var totalReviews: Int
    var incorrectCount: Int
}
```

### ExtractionResult (Codable) — parsed from analyst LLM call

```swift
struct ExtractionResult: Codable {
    struct WordItem: Codable {
        var word: String
        var translation: String
        var context: String?
    }
    struct PhraseItem: Codable {
        var phrase: String
        var meaning: String
    }
    struct ErrorItem: Codable {
        var error: String
        var correction: String
        var rule: String
    }

    var wordsIntroduced: [WordItem]
    var phrasesIntroduced: [PhraseItem]
    var errorsCorrected: [ErrorItem]
    var topicsCovered: [String]
    var studentLifeFact: String?
    var exerciseTypeDelivered: String?
    var estimatedDifficulty: Int?
}
```

---

## Prompt Contracts

### Tutor System Prompt (PromptBuilder.topicSystemPrompt)

**Input:** ESPProfile + session topic
**Output:** System prompt string consumed by the tutor LLM call
**Profile fields used (read-only):**
- `displayName`, `level`, `nativeLanguage`
- `currentStudyTopic` / `sessionGoal`
- `weakAreas` (last 3)
- `lifeNotes` (condensed)
- `wordBank` filtered to `nextDue <= today` (SR words due for review)
- `errorLog` last 2 entries (recent errors to watch)
- `exerciseHistory` last 3 (avoid repeating same exercise type)

**Profile fields NOT written:** The tutor prompt is read-only.

---

### Analyst Extraction Prompt (PromptBuilder.extractionPrompt)

**Input:** user message + tutor reply + student level
**Output:** ExtractionResult JSON
**Model:** gpt-4o-mini
**Temperature:** 0 (deterministic, structured output)
**Max tokens:** 400
**Called by:** ProfileAnalystService (background Task.detached)

---

### Session Summary Prompt (PromptBuilder.sessionSummaryPrompt)

**Input:** full session transcript + topic
**Output:** SessionSummary prose (3-4 sentences)
**Model:** gpt-4o-mini
**Called by:** At session end, or after every 20 messages
**Writes to:** profiles.session_summaries (appended)

---

## Exercise Type Taxonomy

Used in `exercise_history` and `exercise_type_delivered` fields.

| ID | Name | Description |
|---|---|---|
| `conjugation_drill` | Conjugation Drill | Conjugate verb in all 6 persons |
| `gap_fill` | Gap Fill | Complete a sentence with missing word(s) |
| `error_correction` | Error Correction | Find and fix the mistake in a sentence |
| `back_translation` | Back Translation | Translate Spanish → native, then compare |
| `recall` | Active Recall | Produce a word/phrase from memory without cues |
| `generative_use` | Generative Use | Make your own sentence using a target word |
| `minimal_pairs` | Minimal Pairs | Decide between two close options (ser/estar, por/para) |
| `chunk_memorize` | Chunk Memorize | Memorize a multi-word chunk with a memory hook |
| `free_conversation` | Free Conversation | Unstructured practice, no specific drill |

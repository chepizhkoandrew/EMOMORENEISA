# Requirements — Memorization Illustrations

## Goal
When a memorization phrase's audio is generated, also generate a simple, catchy
illustration of the word/phrase. Save it to phone storage the same way audio is
saved, and show it (instead of the static seagull pose) during:

1. The first time the user hears the phrase (`ParrotPlayerView`).
2. Every repetition/refresh session (`SRSPlayerView`).
3. The visual cue slot that currently shows the seagull pose during playback.

The illustration must be memorable and always in a consistent art style so the
user builds a strong mental association. Subjects can be the seagull mascot,
animals, birds, plants, or nature — always relevant to the phrase's meaning.

## Locked decisions (confirmed with user)
- **Model**: Vertex AI **Gemini 2.5 Flash Image** ("nano banana"),
  `gemini-2.5-flash-image`, via Google Cloud (service-account OAuth2), NOT the
  generativelanguage API-key endpoint — to avoid rate limits.
- **Auth**: reuse the existing Cloud TTS service account
  (`GOOGLE_TTS_CREDENTIALS` / `_B64`); Vertex AI is enabled on it. Project ID
  comes from the service-account JSON `project_id` (override `VERTEX_PROJECT_ID`).
- **Billing**: folded into the existing `loro` drill cost — no extra treats
  charged. Raw cost is tracked only.
- **Timing / failure**: fully async, best-effort. Audio never waits for the
  image. If image generation fails, the UI falls back to the seagull pose.

## Constraints
- Keep generation cheap: one image per unique phrase, deduplicated via a shared
  Supabase Storage cache (same pattern as the voice cache).
- Consistent style: a fixed style-anchor prompt prefix; only the subject varies.
- Image bytes stay on-device after download (same as audio); only stats sync.
- Must not break existing `MemoryCard` / `ParrotPhrase` SwiftData schema
  (additive, optional fields only → lightweight migration).

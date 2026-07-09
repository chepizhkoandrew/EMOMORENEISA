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

# Implementation Plan — Memorization Illustrations

See `requirements.md` and `spec.md` in this folder for full detail. Feature:
generate a consistent-style, catchy illustration per memorization phrase (Vertex
AI Gemini 2.5 Flash Image, via the existing Cloud service account), cache it,
save it to phone storage like audio, and show it in place of the seagull cue
during first-hear and every repetition. Fully async/best-effort; falls back to
the seagull pose on failure; no extra treats charged.

### [x] Step: Server config + Vertex image provider
- Add `vertexImage` + `image` config blocks in `server/src/config.js` (reuse Cloud TTS creds, project_id from JSON, `VERTEX_*` / `IMAGE_*` overrides).
- Add matching entries to `server/.env.example`.
- Add `generateIllustration(prompt)` + `buildIllustrationPrompt(spanish, english)` to `server/src/providers.js` (reuse `gcpJwtClient`, `responseModalities:["IMAGE"]`, best-effort null on 429/5xx/empty).

### [x] Step: Image transcode + shared image cache
- New `server/src/image.js`: `pngToJpeg(buf, {quality, maxSize})` via `ffmpeg-static`, fallback to original bytes.
- New `server/src/imagecache.js` mirroring `voicecache.js`: sha256 key over model|style-version|prompt, Supabase bucket `image-cache`, `getIllustration(spanish, english)` returning `{base64, mime, cached}` or null.

### [x] Step: Wire illustration into /v1/loro and /v1/loro/stream
- Kick off illustration generation concurrently with TTS in both endpoints (audio never waits).
- `/v1/loro`: include `illustrationBase64`/`illustrationMime` when present.
- `/v1/loro/stream`: emit `{type:"illustration", base64, mime}` before `done`.
- Record raw image cost for non-cached gens only; treats unchanged; never refund/fail on image error.

### [x] Step: App network + persistence + models
- `ProxyClient.swift`: extend `LoroResult` + `LoroEvent`, parse illustration in `loro`/`loroStream`.
- `ParrotService.swift`: write illustration to `esp-parrot/{id}/illustration.<ext>`, set `phrase.illustrationPath` (clean stale on restart, best-effort).
- `ParrotPhrase.swift` + `MemoryCard.swift`: add optional `illustrationPath` (+ `illustrationURL`); copy in `MemoryCard(from:)`; keep `hasAudio` = 7.

### [x] Step: UI swap + tests
- New `LoroIllustrationView(url:fallback:size:)` showing on-disk image or falling back to `LoroImage(asset:)`.
- Wire into `ParrotPlayerView.playerInfo` (fallback `.teaching`) and `SRSPlayerView.nowPlaying` (fallback `.listening`).
- Ensure `MemoryCardServiceTests` still pass; add a test that `MemoryCard(from:)` copies `illustrationPath`.

### [x] Step: Prompt/visualization tuning + TestFlight 63
- Rewrote `ILLUSTRATION_STYLE_ANCHOR` (warm flat vector children's-book) and `buildIllustrationPrompt` (mnemonic-first, passes both Spanish + English); bumped cache `STYLE_ANCHOR_VERSION` v1→v2.
- Reworked `LoroIllustrationView` to a fixed square card (fill + clip + border) for uniform rendering; verified all 3 display sites (`ParrotPlayerView`, `SRSPlayerView`, `LoroVocabularyView`).
- Added 25s AbortController timeout around the Vertex fetch so a hung call can't hold the loro stream open.
- Shipped TestFlight build 63.

### [x] Step: Fix persistent phrase selection + ship build 64
- `ParrotWordGridView`: added `onDismiss: resetSelection` on the player cover + `resetSelection()` (clears `activePhrase` + `pickedIndices`) so the grid is ready for a new phrase after playback.
- Shipped TestFlight build 64.

### [x] Step: Enable Vertex + deploy server (make illustrations actually appear)
- Root cause of "no illustrations": Vertex AI API was disabled on GCP project `professor-madrid` AND the illustration server code was never deployed (Railway served old code).
- Added `server/scripts/test_illustration.mjs`; ran via `railway run` against production creds — confirmed 403 (API disabled), then enabled `aiplatform.googleapis.com` and re-tested: generation succeeds (~7s, ~23–35KB JPEG, cached to Supabase). Verified style/mnemonic quality across word/greeting/abstract phrases.
- Deployed the local `server/` to Railway (`railway up --service api`); live `/healthz` returns 200 on the new build.

### [x] Step: Fix memory-queue back buttons + slot-spin music
- Back buttons: added a single fixed `BackButton` overlay at `MemorizeContainerView` level (top-leading, `.top 54`/`.leading 16`, mirroring the settings gear) so BOTH tabs (Seagull hub + Progress) share one standard fixed back button. Added `showsBackButton: Bool = true` to `LoroMemorizeHubView`; container passes `false` (renders a 36pt clear placeholder to keep header spacing); the standalone presentation from `AnnotationCanvasView` keeps its own back button via the default. Bumped `LoroStatsView` "Progress" title `.padding(.top, 50)`→`96` to clear the new fixed button.
- Slot music: `HomeView.onChange(of: engine.phase)` now KEEPS `BackgroundMusicPlayer` playing during `.spinning`/`.readyToStart` (was fading out immediately) and only fades out at `.countdown`/`.playing`/`.review`/`.results`. Music now plays under the `slot_spin.mp3` SFX (both `.ambient`+`.mixWithOthers`) while the reels spin. Confirmed `slot_spin.mp3` is bundled via the `Resources/` synchronized root group.

### [x] Step: Tappable Saved Parrot card → consistent replay modal
- Chat "Saved Parrots" card tap did nothing (only the play button worked). Made the phrase/translation area a tap target (`ParrotWordGridView.existingPhraseCard`) that opens a new `replayPhrase` `.fullScreenCover`.
- Added `ParrotReplayView(phrase:onDelete:)` mirroring the memory-queue `VocabularyReplayView` (illustration 160 + phrase + translation + "Replay…" caption + back + trash, auto-plays once via `LoopingParrotPlayer`, TTS fallback) so tapping a Saved Parrot is visually consistent with the Loro memory queue. Trash reuses the card's `deletePhrase`.

### [x] Step: Retroactive illustration fetching for old phrases + build 67/68
- Root cause of "still no picture": screenshots showed OLD phrases ("El cartel", "la esquina") created before illustrations were working — these have `illustrationPath == nil` so `LoroIllustrationView` correctly showed the seagull fallback.
- Added `POST /v1/illustration` server endpoint (free, wraps `getIllustration`, returns `{base64, mime}` or 404) so old phrases can retroactively fetch their illustration.
- Added `ProxyClient.fetchIllustration(spanish:english:)` → `ParrotService.ensureIllustration(for phrase:)` and `ensureIllustration(for card:)` (both no-op if illustration already exists, best-effort).
- Wired `ensureIllustration` into: `ParrotReplayView.task` (chat modal), `ParrotPlayerView.task` (for has-audio path), `VocabularyReplayView.task` (memory queue replay), `SRSPlayerView.task(id:index)` (per-card as queue advances).
- Deployed updated server + shipped TestFlight build 68.

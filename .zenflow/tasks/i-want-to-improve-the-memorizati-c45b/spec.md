# Technical Spec — Memorization Illustrations

## Overview
Add an illustration generation pipeline that runs concurrently with the existing
Loro audio pipeline. Server generates one image per phrase via Vertex AI Gemini
2.5 Flash Image, caches it (Supabase), and returns it alongside audio. The app
saves it to disk next to the audio segments and renders it in the players.

## Server

### 1. Config (`server/src/config.js`)
Add a `vertexImage` block (mirrors `cloudTts`, reuses its credentials):
```
vertexImage: {
  credentials: cloudTts.credentials,       // same service account
  projectId: VERTEX_PROJECT_ID || credentials.project_id,
  location:  VERTEX_LOCATION  (default "global"),
  model:     VERTEX_IMAGE_MODEL (default "gemini-2.5-flash-image"),
  enabled:   VERTEX_IMAGE_ENABLED (default = !!credentials && !!projectId)
}
image: {
  cacheEnabled: IMAGE_CACHE_ENABLED (default true),
  bucket:       IMAGE_CACHE_BUCKET  (default "image-cache"),
  jpegQuality:  IMAGE_JPEG_QUALITY  (default 82),
  maxSize:      IMAGE_MAX_SIZE      (default 512)   // px, longest side
}
```
Add matching entries to `.env.example`.

### 2. Provider (`server/src/providers.js`)
- Reuse `gcpJwtClient()` (scope `cloud-platform`) for the access token.
- `generateIllustration(prompt)`:
  - Host: `location === "global" ? "aiplatform.googleapis.com" : "{loc}-aiplatform.googleapis.com"`.
  - `POST /v1/projects/{proj}/locations/{loc}/publishers/google/models/{model}:generateContent`
  - Body: `{ contents:[{role:"user",parts:[{text: prompt}]}], generationConfig:{ responseModalities:["IMAGE"] } }`
  - Parse `candidates[0].content.parts[].inlineData` → `{ base64, mime }`.
  - Return `null` on 429/5xx/empty (best-effort; never throws to caller).
- `buildIllustrationPrompt(spanish, english)`: fixed STYLE_ANCHOR prefix +
  subject line derived from the meaning. STYLE_ANCHOR (locked so cache stays
  consistent): flat vector children's-book illustration, bold clean outlines,
  warm sunny palette, one clear central subject, soft pastel plain background,
  minimal detail, no text or letters, centered square composition.

### 3. Image transcode (`server/src/image.js`, new)
- `pngToJpeg(buf, {quality, maxSize})` using `ffmpeg-static` (already a dep):
  scale longest side down to `maxSize`, output baseline JPEG. Falls back to the
  original bytes if ffmpeg fails.

### 4. Image cache (`server/src/imagecache.js`, new — mirrors `voicecache.js`)
- Key: `sha256(model | STYLE_ANCHOR_VERSION | prompt)`.
- Bucket `image.bucket`, sharded path `xx/<key>.jpg`, `contentType image/jpeg`.
- `getIllustration(spanish, english)`:
  - cache hit → `{ base64, mime:"image/jpeg", cached:true }`
  - miss → `generateIllustration()` → `pngToJpeg` → `cachePut` →
    `{ base64, mime, cached:false }`
  - provider/gen failure → `null`.

### 5. Endpoints (`server/src/index.js`)
- Kick off illustration generation **concurrently** with audio (start the
  promise before/at the same time as TTS; never `await` it before audio events).
- `/v1/loro` (JSON): await the illustration promise at the end (audio already
  done); include `illustrationBase64` + `illustrationMime` when present (omit on
  failure). Cost/record: add raw image cost only for non-cached generations;
  treats unchanged.
- `/v1/loro/stream` (NDJSON): when the illustration promise resolves, emit
  `{ type:"illustration", base64, mime }` (best-effort, before `done`). If it
  fails, emit nothing. `done` still ends the stream.
- Illustration failure NEVER refunds or fails the request.

## App

### 6. Network (`ProxyClient.swift`)
- `LoroResult`: add `illustration: (data: Data, mime: String)?`.
- `loro(prompt:)`: decode `illustrationBase64`/`illustrationMime`.
- `LoroEvent`: add `case illustration(data: Data, mime: String)`.
- `loroStream`: handle `type == "illustration"`.

### 7. Persistence (`ParrotService.swift`)
- On illustration event/result: write bytes to
  `esp-parrot/{id}/illustration.<ext>` (jpg/png), set
  `phrase.illustrationPath` on MainActor. Clean stale illustration on restart
  (same block that clears audio). Best-effort; ignore write failure.

### 8. Models
- `ParrotPhrase.swift`: add `var illustrationPath: String?` (default nil in
  init) + computed `illustrationURL: URL?`.
- `MemoryCard.swift`: add `var illustrationPath: String?` (default nil) + copy
  it in `init(from:)` + computed `illustrationURL: URL?`. `hasAudio` unchanged
  (still 7 audio paths — illustration is separate, must not affect the count).
- SwiftData: additive optional properties → lightweight migration; no schema
  list change needed in `EMOMORENEISAApp.swift`.

### 9. UI
- New `LoroIllustrationView(url: URL?, fallback: LoroAsset, size:)`: shows the
  on-disk image if `url` exists, else `LoroImage(asset: fallback, size:)`.
- `ParrotPlayerView.playerInfo`: replace `LoroImage(asset:.teaching)` with
  `LoroIllustrationView(url: phrase.illustrationURL, fallback:.teaching)`.
- `SRSPlayerView.nowPlaying`: replace `LoroImage(asset:.listening)` with
  `LoroIllustrationView(url: card.illustrationURL, fallback:.listening)`.

## Testing
- Existing `MemoryCardServiceTests` must still pass (new fields default nil;
  `audioSegmentPaths == segmentPaths` unchanged; `hasAudio` still 7).
- Add a test asserting `MemoryCard(from:)` copies `illustrationPath`.

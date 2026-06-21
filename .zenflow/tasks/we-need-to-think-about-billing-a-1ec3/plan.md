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

# Billing / Secure Proxy — Implementation Plan

Decisions locked with the user: hard paywall (no free tier), 5x margin over loaded COGS, treat ledger hidden from users (sell Conversation Packs), trial grant ~$0.05 COGS, config-driven treat<->COGS ratio, voice toggle, Street View free/day cap then debit, bonus/earn caps, cashback = bonus treats only (never real money). Architecture: Railway = secret-holding proxy + wallet enforcement; Supabase = data.

### [x] Step: Scaffold secure proxy server (server/)
- Express app: /healthz, /v1/chat, /v1/tts, /v1/wallet
- Modules: config (env-driven pricing), auth (Supabase JWT), pricing, wallet (debit RPC, guarded by ENFORCE_WALLET), providers (OpenAI chat/vision, Gemini+OpenAI TTS), meter
- Local smoke test passed (health ok, 401 on unauth, 404)

### [x] Step: Provision Railway + deploy
- Project professor-madrid-api (51821ad3-fee3-46dd-9c1d-75c04436a22d), service "api"
- Non-secret pricing/model env vars set; OPENAI/GEMINI keys pushed (chat+tts features live)
- Public URL https://api-production-ff98.up.railway.app/healthz returns 200
- Custom domain api.professormadrid.com reserved -> CNAME target 4pda4o0n.up.railway.app

### [ ] Step: Finish custom domain (CNAME done; SSL pending)
- Add CNAME at GoDaddy (NS = ns67/ns68.domaincontrol.com): api -> 4pda4o0n.up.railway.app [done by user]
- Apex (Vercel site, 76.76.21.21) left untouched
- Verify SSL issuance on api.professormadrid.com [STILL PENDING: Railway serves wildcard cert, custom-domain cert not issued yet -> curl exit 60]
- App temporarily points at https://api-production-ff98.up.railway.app; switch ProxyBaseURL to api.professormadrid.com once SSL issues

### [x] Step: Supabase schema + service wiring
- Migration 20260621000000_billing_treats.sql applied via Management API
- Tables live: pricing_config (v1 active, 4 packs), wallets, treat_transactions, topups, usage_meter
- RPCs live: ensure_wallet, debit_wallet (atomic, returns insufficient/balance), credit_wallet
- SUPABASE_SERVICE_ROLE_KEY set in Railway; proxy health now reports auth+wallet+chat+tts = true
- RPC flow tested (credit/debit/insufficient/ledger) then test data cleaned up
- ENFORCE_WALLET still false: flip it together with the iOS wiring + trial-grant-on-signup

### [x] Step: Flat per-action debit + StoreKit products in App Store Connect
- Proxy switched to FLAT per-action treat costs (chat 5, voice 2, street view 9) with refund-on-upstream-failure; real COGS still recorded in usage_meter for margin monitoring (decision: flat debit + real-cost metering)
- Margin policy locked: 5x at entry pack, accept volume compression to ~3.75x on $50 pack; bonus curve +0/15/25/48% kept (= 0/13/20/32% real discount)
- 4 consumable IAPs created via App Store Connect API (key V86ZAHA4K5): treats_599=6782526134, treats_1199=6782526074, treats_2499=6782525975, treats_4999=6782526053
- en-US localizations + USD prices (5.99/11.99/24.99/49.99) set; state = MISSING_METADATA (needs review screenshot before submission)
- Proxy redeployed to Railway; health = chat+tts+wallet+auth all true

### [x] Step: Point iOS app at proxy + remove shipped keys
- Added ProxyClient (JWT-authed gateway), WalletManager, StoreManager (StoreKit 2), PaywallView
- Rewired ChatOpenAIService / TTSService / ParrotService / ProfileAnalystService to the proxy; keys removed from Info.plist + Secrets.xcconfig (leaked keys still MUST be rotated in OpenAI/Google consoles)
- Wallet bootstrap + paywall sheet + treats pill wired into SessionListView; treats balance + top-up + auto-voice toggle added to ProfileView
- Auto-voice toggle (AppStorage autoVoiceEnabled) gates automatic TTS in ChatView + ThreadSheetView
- StoreManager.creditOnServer uses VerificationResult.jwsRepresentation (StoreKit 2)
- xcodebuild: BUILD SUCCEEDED (generic iOS Simulator, Debug)
- StoreKit topup verified server-side against Apple Root CA-G3

### [ ] Step: Flip enforcement + release prep (do LAST)
- [x] ENFORCE_WALLET=true set on Railway (hard paywall now live server-side)
- [x] Test grant: andrii.chepizhko@gmail.com (uid f1714f63-...) credited 5000 treats, has_paid=true
- [x] Auth gate: HomeView now requires sign-in AFTER intro, BEFORE mode selection (verb game / memorize no longer reachable logged-out); build SUCCEEDED
- [x] Key rotation: SKIPPED per user (no testers/downloads except owner)
- [x] Deployed build 9 to TestFlight via `fastlane beta` (archive+export+upload SUCCEEDED; Apple-side processing async)
- [x] Billing verified end-to-end on live enforced backend via server/test/billing-smoke.mjs (real Supabase JWT, no backdoor): trial=50, chat debits 5, 402 at 0 balance for chat AND tts, service-role refill restores -> PASS
- [x] Custom-domain cert: LIVE. User re-created the Railway custom domain registration, ACME completed, cert CN=api.professormadrid.com issued. https://api.professormadrid.com/healthz returns 200 with chat/tts/wallet/auth all true. Info.plist ProxyBaseURL flipped from https://api-production-ff98.up.railway.app to https://api.professormadrid.com. Next fastlane beta build ships on the custom domain. (Note: the TXT record the user briefly added was unnecessary — Railway validates via TLS-ALPN-01, not DNS-01 — and can be removed.)
- [ ] Upload IAP review screenshots (4 consumables in MISSING_METADATA)
- [ ] Real IAP purchase path requires an Apple Sandbox tester (local .storekit fails server JWS verify against Apple Root CA-G3)

### [x] Step: Loro voice generation fix (server-side, no app update needed)
- [x] Root cause #1: silent cross-language fallback — on any Gemini TTS failure the server switched to OpenAI tts-1 (English voice) and spoke Spanish words with an English accent. Removed: synthesizeVoice() in server/src/providers.js is now Gemini-ONLY (OpenAI off behind TTS_ALLOW_OPENAI_FALLBACK=false, never used for Spanish).
- [x] Root cause #2: Gemini preview TTS is rate-limited (~10 RPM). 7 sequential/parallel segments hit 429 -> null -> English fallback. Fix: dedupe segments — the 7 positions are only 4 unique strings (Spanish word repeats 4x), so /v1/loro now synthesizes each DISTINCT text once and fans buffers back out (7 -> 4 calls). Bounded concurrency (LORO_TTS_CONCURRENCY=2).
- [x] Root cause #3 (the real intermittent bug): Gemini returns HTTP 200 with NO audio part intermittently; geminiTTSOnce treated empty-200 as non-retryable and gave up, dropping a segment. Fixed: empty-200 is now retryable. Retry/backoff with full jitter (TTS_RETRIES=3, TTS_RETRY_BASE_MS=600) across primary+fallback Gemini models.
- [x] /v1/loro response shape unchanged (segments[] of {audioBase64,mime}); ships with ZERO app change. Fails honestly + refunds treats if any segment truly can't be voiced (no English audio ever).
- [x] All config-driven in server/src/config.js (tts block + models.ttsGeminiFallback).
- [x] Verified live on https://api.professormadrid.com via server/test/loro-smoke.mjs (real Supabase JWT, no backdoor): 3/3 runs PASS, 7/7 Gemini segments, no audio/wav (no OpenAI fallback), ~6s latency.
- [x] FOLLOW-UP DONE: true progressive/streaming playback. New NDJSON endpoint POST /v1/loro/stream (server/src/index.js) emits meta -> per-position segment events (Spanish word/index 0 first) -> done; same single flat "loro" debit + refund-on-failure as /v1/loro (kept intact for old builds). iOS: ProxyClient.loroStream() (AsyncThrowingStream over URLSession.bytes), ParrotService.generateStreaming() writes each N.wav atomically as it lands + fires onFirstSegment, LoopingParrotPlayer.startStreaming() resolves segment URLs on demand and buffers (poll 0.2s, cap 150) until each file appears, ParrotPlayerView.task starts playback on first segment. Verified live via server/test/loro-stream-smoke.mjs: PASS, 7/7 Gemini positions, no English fallback, first segment 3.5s vs full set 5.6s (2.1s streaming head start).
- [x] Deployed streaming endpoint to Railway (api.professormadrid.com healthy; route returns 401 not 404).
- [x] fastlane beta build 10 (1.0) ARCHIVE+EXPORT+UPLOAD SUCCEEDED, processed on TestFlight. Ships streaming playback + the api.professormadrid.com domain cutover (ProxyBaseURL already flipped in Info.plist).

### [x] Step: Shared audio cache (Supabase Storage) + AAC compression
- [x] Server: pcmToAac() via ffmpeg-static (server/src/audio.js) — PCM s16le 24kHz mono -> AAC-LC ADTS @ AAC_BITRATE (40k). Verified locally: valid ADTS sync word, ~6.7x compression on synthetic tone (real speech higher).
- [x] Server: voicecache.js — cache-fronted getVoice(text,{format}); sha256(model|voice|bitrate|text) key, sharded object path (ab/<hash>.aac), idempotent private bucket. Cache hit = no Gemini call ($0 raw cost). All cache failures swallowed (never break a request).
- [x] Server: config.audio block (AUDIO_CACHE_ENABLED/AUDIO_CACHE_BUCKET/AAC_BITRATE); .env.example updated.
- [x] Server: /v1/tts, /v1/loro, /v1/loro/stream read `format` from body and call getVoice; metering bills only uncached (Gemini-hitting) seconds, tags provider:"cache" on hits. Legacy builds omit `format` -> default PCM -> unchanged.
- [x] iOS: ProxyClient sends `format:"aac"` on tts/loro/loro-stream; ParrotService.decodeSegment writes correct extension (aac/m4a/wav); LoopingParrotPlayer.urlForSegment + TTSService.fetchTTS/cachedChunkURL scan aac/m4a/wav (AAC played natively, only PCM WAV-wrapped).
- [x] Deployed to Railway; voice-cache bucket auto-created. Stream smoke test (format:"aac") PASS 2x: run1 all-AAC 7/7, firstSeg 7.7s; run2 CACHE HIT firstSeg 1.6s / full 4.9s (no Gemini). No English fallback.
- [ ] fastlane beta Build 11 (ships iOS AAC end-to-end + api.professormadrid.com domain)

### [ ] Step: Billing model doc + StoreKit products
- Conversation Pack tiers ($5.99/$11.99/$24.99/$49.99) with bonus curve
- Earn/bonus caps, expiry/breakage policy, T&C pricing schema

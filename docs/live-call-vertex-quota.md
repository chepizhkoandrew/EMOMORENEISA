# Live Call: Vertex AI concurrency quota for `gemini-3.8-live`

Research date: 2026-11-26. Project `professor-madrid`. Everything here was read-only: no quotas, billing, IAM or deployments were changed.

## TL;DR

- **The limit is 1,000 concurrent Live sessions** per project for `gemini-3.8-live` in `us-central1`. This is the default and has no override. The quota is not "a handful" of sessions, so it does not block a wide launch.
- **Observed:** 5, 10, 20 and 50 overlapping sessions in `us-central1`, and 20 on the EU multi-region endpoint, all reached `setupComplete` with zero refusals. I did not try to hit the 1,000 ceiling.
- **A second location does exist.** On 2026-11-26 `gemini-3.8-live` answered on:
  - the **EU multi-region** endpoint (`aiplatform.eu.rep.googleapis.com`, location `eu`). It took about 360–450 ms to reach setupComplete, versus about 930 ms for us-central1, measured from a Mac in Europe. It is much closer to Railway's europe-west4.
  - the **US multi-region** endpoint (`aiplatform.us.rep.googleapis.com`, location `us`).
  - `asia-south1`, with an 800-session quota.

  The earlier "not found" results came from regional europe-* and us-east4 endpoints and from `global`. Those still fail. The multi-region endpoints are different hosts.
- **Raise the quota** under Console → IAM & Admin → **Quotas & System Limits**, filtering for `gemini-3.8-live`. See the "How to raise it" section below.
- **Bigger launch risks than the quota:** per-turn re-billing of the whole context window, which drives cost, and the single Node relay process, which limits capacity. See the "Other things that will bite before the quota does" section.

## 1. Current quota values (Service Usage API, read 2026-11-26)

Metric `aiplatform.googleapis.com/bidi_gen_concurrent_reqs_per_project_per_base_model`, display name "Bidi generate content concurrent requests per project per region per base model". Its unit is `1/10min/{project}/{region}/{base_model}`, but it behaves as a concurrent count.

| Location | Base model | Effective limit | Override |
|---|---|---|---|
| us-central1 | gemini-3.8-live | **1000** | none (default) |
| asia-south1 | gemini-3.8-live | 800 | none |
| us-central1 / europe-west4 / 12 other regions | gemini-live-2.5-flash-native-audio | 5000 | none |
| us-central1 / europe-* / us-* | gemini-3.1-flash-live-preview-04-2026 | 1000 | none |

Metric `…/bidi_gen_concurrent_reqs_per_project_per_base_model_global` ("…for global endpoint"): `gemini-3.8-live` = **1000**. The avatar variant of this metric is labelled "for global and multi-region endpoints". The `eu`/`us` multi-region Live sessions most likely draw from this pool. I did not confirm whether `eu` and `us` share one 1,000 pool or each get 1,000.

Other relevant values:
- Avatar sessions (`…with_avatar…`) for gemini-3.8-live: 100 in us-central1, 50 in asia-south1, and 100 global. We don't use the avatar, so these don't apply.
- Token-per-minute quotas (`online_prediction_*_tokens_per_minute_per_base_model`, `eu_multi_region_*`, `us_multi_region_*`) have no fixed per-model value set. That points to Gemini's **Dynamic Shared Quota** for throughput: no hard per-project TPM, but you can get 429s when the shared pool is busy. The docs don't confirm explicitly that DSQ covers the Live API. The concurrency cap above is a fixed, separate quota.
- I found no Provisioned Throughput on the project, because no PT-related quota buckets or overrides exist. Usage is plain pay-as-you-go.

How these were read: the `gcloud beta quotas` component isn't installed, and the Cloud Quotas API (`cloudquotas.googleapis.com`) is **disabled** on the project. So I used `serviceusage.googleapis.com/v1beta1/projects/professor-madrid/services/aiplatform.googleapis.com/consumerQuotaMetrics?view=FULL` with `gcloud auth print-access-token --account=andrii.chepizhko@gmail.com`. Enabling the Cloud Quotas API is harmless if you want the gcloud command to work later.

## 2. Empirical test

Script: opens N WebSockets in parallel to `wss://<host>/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent` with the server's service account. It sends only `setup` (AUDIO modality, a one-line system prompt), keeps every socket open until all of them have answered, then closes them. No audio was sent, so the cost was effectively zero.

| Endpoint / location | Model | N | setupComplete | p50 / max setup latency |
|---|---|---|---|---|
| us-central1 | gemini-3.8-live | 5 | 5/5 | 944 / 991 ms |
| us-central1 | gemini-3.8-live | 10 | 10/10 | 914 / 982 ms |
| us-central1 | gemini-3.8-live | 20 | 20/20 | 904 / 993 ms |
| us-central1 | gemini-3.8-live | 50 | 50/50 | 926 / 1069 ms |
| `aiplatform.eu.rep.googleapis.com`, loc `eu` | gemini-3.8-live | 20 | 20/20 | **363 / 639 ms** |
| `aiplatform.us.rep.googleapis.com`, loc `us` | gemini-3.8-live | 1 | 1/1 | 729 ms |
| asia-south1 | gemini-3.8-live | 1 | 1/1 | 2826 ms |
| europe-west4 | gemini-live-2.5-flash-native-audio | 1 | 1/1 | 334 ms |
| us-central1 | gemini-live-2.5-flash-native-audio | 1 | 1/1 | 994 ms |
| global | gemini-3.8-live | 1 | **fail**: close 1008 "Publisher model … was not found or your project does not have access" | – |
| europe-west4 | gemini-3.8-live | 1 | **fail**: close 1008, same message | – |
| europe-west4 | gemini-3.1-flash-live-preview-04-2026 | 1 | **fail**: close 1008, same message | – |
| `eu-aiplatform.googleapis.com` / `us-aiplatform.googleapis.com` | – | 1 | HTTP 404. Wrong host form: multi-region uses `aiplatform.<mr>.rep.googleapis.com` | – |

Latency was measured from the Mac, not from Railway. From Railway's europe-west4 the gap between EU and us-central1 should be similar or larger.

To use the EU endpoint, the relay needs a host override, because the current code builds `${loc}-aiplatform.googleapis.com` (`server/src/live.js` `vertexWsUrl()`). For location `eu`, the host must be `aiplatform.eu.rep.googleapis.com`. The model path is `projects/professor-madrid/locations/eu/publishers/google/models/gemini-3.8-live`. Data residency is a bonus: the processing stays in the EU.

## 3. What a user hits when the quota is exceeded

Not observed: we never got near 1,000. Google's docs don't document the Live-specific error. They say only that the session check happens "when a session starts" and that "the task … fails". Based on how Vertex reports other quota errors, expect the upstream WebSocket to **close right after `setup`, before `setupComplete`**. The close code is likely 1011 or 1008, with a reason containing `RESOURCE_EXHAUSTED` / `Quota exceeded` / `429`. The HTTP upgrade itself could also be rejected with 429. The "model not found" case above shows the pattern: close **1008** with a text reason.

What the relay does today (`server/src/live.js`):
- The upstream `close` handler logs the reason and then calls `upstreamFailed(\`ws_${code}\`)`.
- On a first-connect failure, the phone gets `{relay:{error:"connection_failed", detail:"ws_1008"}}` and the session ends.
- **The reason text is dropped**, so the app can't tell "busy" apart from any other failure.

Suggested handling (not implemented):
- In the upstream close handler, map `/RESOURCE_EXHAUSTED|quota|exhausted|429|rate/i` in the reason, or an HTTP 429 `unexpected-response`, to `{relay:{error:"busy"}}`.
- In the app, show a friendly message for `busy`, something like "Professor Madrid is on many calls right now — try again in a minute."
- The refund is already handled: when a session never connects upstream, `end()` refunds the pre-debited first minute.
- Optionally fail over to a second location (for example `eu` → `us-central1`) when the connect fails with `busy`.

## 4. How to raise it

1. Console: <https://console.cloud.google.com/iam-admin/quotas?project=professor-madrid> → filter **"Bidi generate content concurrent requests"** or `gemini-3.8-live`. Select the row for the location you use: `region: us-central1`, or the global / multi-region row if you switch to `eu`. Then choose **Edit quota**, enter the new value, add a justification, and choose **Submit request**. Use the account andrii.chepizhko@gmail.com. The API reports the limit as not `isFixed`, so it is adjustable.
2. Lead time: Google doesn't publish one for this quota. In practice, Vertex gen-AI increases take anywhere from minutes (auto-approved) to 2–3 business days. Large jumps (say 1,000 → 10,000) may be sent to sales or the account team. Some multimodal quotas are documented as "contact your account team; can't be increased from the console". That note doesn't name the Live concurrency quota.
3. **Provisioned Throughput** buys guaranteed *throughput*, not concurrency headroom, and isn't needed to scale past 1,000. Concurrency stays capped by the quota above.
   - It is sized in GSUs: 1 GSU = 1,350 burndown-tokens/s. Burndown multipliers: input audio 4, output audio 16, text in 1 / text out 6.
   - Google's example: **10 concurrent 5-minute sessions ≈ 69 GSUs**.
   - Sessions that don't fit go to PayGo at session start; there is no mid-session spillover.
   - PT is a monthly or yearly commitment and only makes sense at high sustained volume.
4. More capacity without a quota request: the `eu`, `us` and `asia-south1` locations each have their own buckets (exception: `eu`/`us` may share the global one, see section 1). `gemini-live-2.5-flash-native-audio` has **5,000** per region and runs in europe-west4. It is an older model with different voice quality, so it is a fallback, not a like-for-like swap.

## 5. Session limits (Live API docs)

- Without context window compression, sessions are capped at 15 min for audio-only (2 min with video). The relay enables `contextWindowCompression.slidingWindow`, so sessions can run past that.
- A single WebSocket connection lives about **10 minutes**. The server sends `goAway` about 60 s before cutting it. The relay already handles this by reconnecting with a session-resumption handle.
- Context window: 128k tokens. Audio is 25 tokens/s.
- Docs also list "5,000 concurrent sessions per project, 4M tokens/min" as generic Live API limits, and "1,000 concurrent sessions by default" for 2.5 native audio. They conflict with each other. The project's own quota values in section 1 are what count.

## 6. Price (Vertex, gemini-3.8-live, non-global, per 1M tokens)

| | USD / 1M tokens |
|---|---|
| Input text | $0.75 |
| Input audio | $3.00 |
| Input image/video | $1.00 |
| Output text (incl. transcription text) | $4.50 |
| Output audio | $12.00 |

Audio = 25 tokens/s, so 1 min of user speech = 1,500 tokens ≈ $0.0045 and 1 min of tutor speech ≈ $0.018. **Important:** Live is billed *per turn on the whole session context window*: earlier turns are re-processed and re-billed as input every turn, up to the context size. A rough 10-minute call with a turn every ~15 s has ~40 turns. By turn 40 it is re-billing ~25k tokens a turn, which totals ≈ 0.5M input tokens ≈ **$1.5–1.7 per 10 min**. Cost grows roughly quadratically with call length until compression trims the context.

Lowering `contextWindowCompression.triggerTokens` would cap the per-turn cost, at the price of shorter memory. The valid range is 5k–128k, and the relay sends the default today. This estimate is unverified; check it against real billing (Billing → Reports, SKU "Gemini 3.8 Live") after a few real calls. Compare it with the 20 treats/minute the app charges (`COST_LIVE_MINUTE`).

## 7. Other things that will bite before the quota does

- **The relay is a single process.** It keeps every session in an in-memory `Map` on one Railway instance and pipes PCM both ways (16 kHz in ≈ 32 KB/s, 24 kHz out ≈ 48 KB/s). 1,000 calls is about 80 MB/s through one Node process. Load-test the relay before relying on the Vertex quota, and note that sessions can't move between Railway replicas.
- **Access tokens:** one JWT client is shared and cached. That's fine.

## Sources

- Live API session management: <https://docs.cloud.google.com/vertex-ai/generative-ai/docs/live-api/start-manage-session>
- Live API reference (rate limits): <https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/multimodal-live>
- Gen AI quotas & system limits: <https://docs.cloud.google.com/vertex-ai/generative-ai/docs/quotas>
- Provisioned Throughput for Live API: <https://docs.cloud.google.com/vertex-ai/generative-ai/docs/provisioned-throughput/live-api>
- Gemini 3.8 Live model page (locations us / eu / us-central1): <https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-8-live>
- Pricing: <https://cloud.google.com/vertex-ai/generative-ai/pricing>

import crypto from "node:crypto";
import { supabase } from "./supabase.js";
import { config } from "./config.js";
import { synthesizeVoice, textToSsml } from "./providers.js";
import { pcmToAac } from "./audio.js";

const AAC_MIME = "audio/aac";

let bucketReady = false;

// Idempotently ensure the private storage bucket exists. Safe to call repeatedly;
// the "already exists" error is swallowed.
async function ensureBucket() {
  if (bucketReady || !config.audio.cacheEnabled) return;
  const sb = supabase();
  if (!sb) return;
  try {
    await sb.storage.createBucket(config.audio.bucket, { public: false });
  } catch (_) { /* already exists / racing instance */ }
  bucketReady = true;
}

// One audio artifact per distinct (model, voice, bitrate, text). Different voices
// or a model/bitrate change produce a different key, so the cache never serves
// stale audio after a config change.
// Signature of the active PRIMARY voice engine. Switching engines/voices (e.g.
// Gemini -> Google Cloud Chirp 3 HD) changes this tag, so the cache never serves
// audio rendered by a different voice.
export function activeVoiceTag(voiceOverride = null) {
  if (voiceOverride?.voiceName) {
    return `gcloud|${voiceOverride.languageCode || config.cloudTts.languageCode}|${voiceOverride.voiceName}|${config.cloudTts.speakingRate}`;
  }
  if (config.cloudTts.enabled) {
    return `gcloud|${config.cloudTts.languageCode}|${config.cloudTts.voiceName}|${config.cloudTts.speakingRate}`;
  }
  return `${config.models.ttsGemini}|${config.tts.voiceName}`;
}

// Cache key is derived from the rendered SSML (not raw text) so the same text
// with different contexts (e.g. "label" vs "sentence") gets separate cache
// entries — and from voiceOverride, so a roleplay object's voice never
// collides with Madrid's cached line for the same text.
function cacheKey(text, context = "default", voiceOverride = null) {
  const ssmlOrText = config.cloudTts.enabled ? textToSsml(text, context) : text;
  return crypto
    .createHash("sha256")
    .update(`${activeVoiceTag(voiceOverride)}|${config.audio.aacBitrate}|${ssmlOrText}`)
    .digest("hex");
}

// Shard by the first 2 hex chars so a bucket never holds a single huge flat list.
function objectPath(key) {
  return `${key.slice(0, 2)}/${key}.aac`;
}

async function cacheGet(key) {
  if (!config.audio.cacheEnabled) return null;
  const sb = supabase();
  if (!sb) return null;
  try {
    const { data, error } = await sb.storage.from(config.audio.bucket).download(objectPath(key));
    if (error || !data) return null;
    const buf = Buffer.from(await data.arrayBuffer());
    return buf.length ? buf : null;
  } catch (_) {
    return null;
  }
}

async function cachePut(key, buf) {
  if (!config.audio.cacheEnabled) return;
  const sb = supabase();
  if (!sb) return;
  try {
    await ensureBucket();
    await sb.storage.from(config.audio.bucket).upload(objectPath(key), buf, {
      contentType: AAC_MIME,
      upsert: true
    });
  } catch (_) { /* best-effort: a cache write failure must never break a request */ }
}

// Voice synthesis with the shared AAC cache in front of Gemini.
//
// format:
//   "aac" — new app builds. Serves the cached AAC if present (no Gemini call),
//           otherwise synthesizes PCM, transcodes to AAC, caches it, and returns AAC.
//   "pcm" — legacy app builds (default). Behaviour is unchanged (fresh PCM each
//           time) but a cache-miss still warms the AAC cache in the background so
//           newer builds benefit. Old clients wrap PCM into WAV on-device.
//
// allowOpenAIFallback defaults to true so every existing caller's behavior is
// unchanged. Pass false for pre-generation callers (see
// scripts/render-say-it-better-assets.js) that must guarantee a clip is never
// voiced by OpenAI, even on a Cloud TTS + Gemini outage.
//
// Returns { provider, audioBase64, mime, cached } or null when synthesis fails.
export async function getVoice(text, { format = "pcm", context = "default", voiceOverride = null, allowOpenAIFallback = true } = {}) {
  const key = cacheKey(text, context, voiceOverride);

  if (format === "aac" && config.audio.cacheEnabled) {
    const hit = await cacheGet(key);
    if (hit) {
      return { provider: "cache", audioBase64: hit.toString("base64"), mime: AAC_MIME, cached: true };
    }
  }

  const pcm = await synthesizeVoice(text, { allowOpenAIFallback, context, voiceOverride });
  if (!pcm) return null;

  // OpenAI fallback audio is live-only — must not pollute the shared cache.
  const cacheable = pcm.provider !== "openai";

  if (format === "aac") {
    try {
      const aac = await pcmToAac(Buffer.from(pcm.audioBase64, "base64"));
      if (cacheable) await cachePut(key, aac);
      return { provider: pcm.provider, audioBase64: aac.toString("base64"), mime: AAC_MIME, cached: false };
    } catch (_) {
      return { provider: pcm.provider, audioBase64: pcm.audioBase64, mime: pcm.mime, cached: false };
    }
  }

  if (config.audio.cacheEnabled && cacheable) {
    pcmToAac(Buffer.from(pcm.audioBase64, "base64"))
      .then((aac) => cachePut(key, aac))
      .catch(() => {});
  }
  return { provider: pcm.provider, audioBase64: pcm.audioBase64, mime: pcm.mime, cached: false };
}

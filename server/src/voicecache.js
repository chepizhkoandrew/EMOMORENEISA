import crypto from "node:crypto";
import { supabase } from "./supabase.js";
import { config } from "./config.js";
import { synthesizeVoice } from "./providers.js";
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
function cacheKey(text) {
  return crypto
    .createHash("sha256")
    .update(`${config.models.ttsGemini}|${config.tts.voiceName}|${config.audio.aacBitrate}|${text}`)
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
// Returns { provider, audioBase64, mime, cached } or null when synthesis fails.
export async function getVoice(text, { format = "pcm" } = {}) {
  if (format === "aac" && config.audio.cacheEnabled) {
    const hit = await cacheGet(cacheKey(text));
    if (hit) {
      return { provider: "cache", audioBase64: hit.toString("base64"), mime: AAC_MIME, cached: true };
    }
  }

  const pcm = await synthesizeVoice(text);
  if (!pcm) return null;

  if (format === "aac") {
    try {
      const aac = await pcmToAac(Buffer.from(pcm.audioBase64, "base64"));
      await cachePut(cacheKey(text), aac);
      return { provider: pcm.provider, audioBase64: aac.toString("base64"), mime: AAC_MIME, cached: false };
    } catch (_) {
      // Transcode failed — still serve the user raw PCM so playback works.
      return { provider: pcm.provider, audioBase64: pcm.audioBase64, mime: pcm.mime, cached: false };
    }
  }

  // Legacy PCM response; warm the AAC cache out-of-band for future aac requests.
  if (config.audio.cacheEnabled) {
    pcmToAac(Buffer.from(pcm.audioBase64, "base64"))
      .then((aac) => cachePut(cacheKey(text), aac))
      .catch(() => {});
  }
  return { provider: pcm.provider, audioBase64: pcm.audioBase64, mime: pcm.mime, cached: false };
}

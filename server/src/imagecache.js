import crypto from "node:crypto";
import { supabase } from "./supabase.js";
import { config } from "./config.js";
import { generateIllustration, buildIllustrationPrompt } from "./providers.js";
import { pngToJpeg } from "./image.js";

const JPEG_MIME = "image/jpeg";

// Bump when the style anchor / prompt shape changes so the cache never serves
// an image rendered in a now-stale style.
// v2: mnemonic-focused prompt + refined style anchor (stronger association).
// v3: switched from square (1:1, unset -> defaulted square) to 3:4 portrait
// — square images looked stretched/cropped everywhere they're shown full-bleed
// (karaoke background, memory-card hero).
const STYLE_ANCHOR_VERSION = "v3";

let bucketReady = false;

// Idempotently ensure the private storage bucket exists. Safe to call
// repeatedly; the "already exists" error is swallowed.
async function ensureBucket() {
  if (bucketReady || !config.image.cacheEnabled) return;
  const sb = supabase();
  if (!sb) return;
  try {
    await sb.storage.createBucket(config.image.bucket, { public: false });
  } catch (_) { /* already exists / racing instance */ }
  bucketReady = true;
}

// One image per distinct (model, style version, prompt). Changing the model or
// bumping STYLE_ANCHOR_VERSION produces a different key, so the cache never
// serves an illustration made under a different style.
function cacheKey(prompt) {
  return crypto
    .createHash("sha256")
    .update(`${config.vertexImage.model}|${STYLE_ANCHOR_VERSION}|${prompt}`)
    .digest("hex");
}

// Shard by the first 2 hex chars so a bucket never holds a single huge flat list.
function objectPath(key) {
  return `${key.slice(0, 2)}/${key}.jpg`;
}

async function cacheGet(key) {
  if (!config.image.cacheEnabled) return null;
  const sb = supabase();
  if (!sb) return null;
  try {
    const { data, error } = await sb.storage.from(config.image.bucket).download(objectPath(key));
    if (error || !data) return null;
    const buf = Buffer.from(await data.arrayBuffer());
    return buf.length ? buf : null;
  } catch (_) {
    return null;
  }
}

async function cachePut(key, buf) {
  if (!config.image.cacheEnabled) return;
  const sb = supabase();
  if (!sb) return;
  try {
    await ensureBucket();
    await sb.storage.from(config.image.bucket).upload(objectPath(key), buf, {
      contentType: JPEG_MIME,
      upsert: true
    });
  } catch (_) { /* best-effort: a cache write failure must never break a request */ }
}

// Illustration for a phrase with the shared JPEG cache in front of Vertex.
// Returns { base64, mime, cached } or null when generation is unavailable /
// fails (best-effort — the caller falls back to the seagull pose).
export async function getIllustration(spanish, english) {
  const prompt = buildIllustrationPrompt(spanish, english);
  const key = cacheKey(prompt);

  const hit = await cacheGet(key);
  if (hit) {
    return { base64: hit.toString("base64"), mime: JPEG_MIME, cached: true };
  }

  const raw = await generateIllustration(prompt);
  if (!raw?.base64) return null;

  try {
    const jpeg = await pngToJpeg(Buffer.from(raw.base64, "base64"));
    await cachePut(key, jpeg);
    return { base64: jpeg.toString("base64"), mime: JPEG_MIME, cached: false };
  } catch (_) {
    // Transcode failed — still return the original bytes so the user gets art.
    return { base64: raw.base64, mime: raw.mime || "image/png", cached: false };
  }
}

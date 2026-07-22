// Pre-warms the shared voice cache (Supabase Storage, AAC — the same cache
// `getVoice()` / `voicecache.js` uses for every other TTS call in the app)
// with every clip a Say It Better lesson's explanation autoplay will ever
// request, so the client's real playback (TTSService.speakTurn, context:
// "sentence") is always a cache hit — never a live synthesis call, and
// never able to fall back to OpenAI, in front of a real user.
//
// This does NOT write any audio files of its own — populating the cache is
// entirely a side effect of calling the same `getVoice()` every real request
// already calls. The only on-disk output here is a manifest for auditing
// which provider actually produced each clip (must never be "openai").
//
// CRITICAL: the iOS client (TTSService.swift, `splitTextIntoChunks`) splits
// each explanation bubble's text into up to 3 chunks at specific
// sentence-boundary offsets *before* requesting TTS — the cache is keyed per
// chunk substring, not the whole bubble text. `splitTextIntoChunks` below is
// a deliberate line-for-line port of that Swift function; if the two ever
// drift, every real playback becomes a silent, permanent cache miss. Do not
// "simplify" this without updating both sides together.
//
// Usage:
//   node server/scripts/render-say-it-better-assets.js --dry
//   node server/scripts/render-say-it-better-assets.js
//   node server/scripts/render-say-it-better-assets.js --only=goodbye
//
// Requires the same env as the running proxy (Google Cloud service account
// for Chirp3 HD / GEMINI_API_KEY, SUPABASE_* for the cache bucket) — run this
// with production-equivalent config so the cache keys it writes match what
// the deployed server will look up (activeVoiceTag() and the Cloud-TTS-vs-not
// branch in cacheKey() both depend on config/credentials being present).

import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { getVoice, activeVoiceTag } from "../src/voicecache.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const RESOURCES_DIR = join(REPO_ROOT, "EMOMORENEISA", "EMOMORENEISA", "EMOMORENEISA", "Resources");
const MANIFEST_PATH = join(__dirname, "say-it-better-render-manifest.json");

const args = process.argv.slice(2);
const DRY = args.includes("--dry");
const ONLY_LESSON = args.find(a => a.startsWith("--only="))?.split("=")[1];

// ---------------------------------------------------------------------------
// Line-for-line port of TTSService.swift's splitTextIntoChunks/sentenceBoundary.
// Operates on Unicode code points (Array.from) to mirror Swift's Character-
// based indexing — correct for this content (plain English/Ukrainian
// narration, no emoji/combining marks). Note: Swift only trims .whitespaces
// (not newlines) on the split-out chunks, vs. JS's .trim() trimming both —
// harmless here since none of this content has embedded newlines.
// ---------------------------------------------------------------------------

function sentenceBoundary(chars, afterOffset) {
  if (chars.length <= afterOffset) return null;
  for (let idx = afterOffset; idx < chars.length; idx++) {
    const ch = chars[idx];
    const nextIdx = idx + 1;
    const isBoundaryChar = ch === "." || ch === "!" || ch === "?";
    if (isBoundaryChar && (nextIdx === chars.length || chars[nextIdx] === " " || chars[nextIdx] === "\n")) {
      return nextIdx;
    }
  }
  return null;
}

function splitTextIntoChunks(text) {
  const t = text.trim();
  const tChars = Array.from(t);
  if (tChars.length <= 60) return [t];

  const s1 = sentenceBoundary(tChars, 40);
  if (s1 === null) return [t];
  const c1 = tChars.slice(0, s1).join("").trim();
  const rest1 = s1 < tChars.length ? tChars.slice(s1).join("").trim() : "";
  if (!rest1) return [c1];

  const rest1Chars = Array.from(rest1);
  const s2 = sentenceBoundary(rest1Chars, 30);
  if (s2 === null) return [c1, rest1];
  const c2 = rest1Chars.slice(0, s2).join("").trim();
  const c3 = s2 < rest1Chars.length ? rest1Chars.slice(s2).join("").trim() : "";

  return [c1, c2, c3].filter(s => s.length > 0);
}

// ---------------------------------------------------------------------------
// Content discovery — reads the exact same bundled JSON the app ships, so
// there is exactly one source of truth (no separately hand-synced BANK
// object to drift out of date, unlike the onboarding script's precedent).
// ---------------------------------------------------------------------------

function findLessonFiles() {
  return readdirSync(RESOURCES_DIR)
    .filter(f => f.startsWith("sayItBetter_") && f.endsWith(".json"))
    .filter(f => !ONLY_LESSON || f === `sayItBetter_${ONLY_LESSON}.json`);
}

// Every string the explanation autoplay will ever narrate, across both
// locales it can render in (see ExplanationChunk.text(for:) in
// SayItBetterModels.swift — falls back to English if a locale is missing).
function collectExplanationStrings(lesson) {
  const strings = [];
  for (const chapter of lesson.chapters) {
    for (const chunk of chapter.explanation) {
      for (const locale of Object.keys(chunk.textByLocale)) {
        strings.push(chunk.textByLocale[locale]);
      }
    }
  }
  return strings;
}

async function renderChunk(text) {
  const audio = await getVoice(text, { format: "aac", context: "sentence", allowOpenAIFallback: false });
  if (!audio) throw new Error(`tts_failed for: ${text.slice(0, 60)}...`);
  return audio;
}

async function main() {
  const voiceTag = activeVoiceTag();
  console.log(`[say-it-better] Voice tag: ${voiceTag}`);
  if (DRY) console.log("[say-it-better] DRY RUN — will print the plan, call nothing");

  const files = findLessonFiles();
  if (files.length === 0) {
    console.warn("[say-it-better] no sayItBetter_*.json files found — nothing to do");
    return;
  }

  const manifest = { voiceTag, renderedAt: DRY ? "dry-run" : new Date().toISOString(), lessons: {} };
  let sawOpenAI = false;
  let sawLiveSynthesis = false;

  for (const file of files) {
    const lesson = JSON.parse(readFileSync(join(RESOURCES_DIR, file), "utf8"));
    console.log(`\n[say-it-better] Lesson: ${lesson.id} (${file})`);

    const explanationStrings = collectExplanationStrings(lesson);
    const seenChunks = new Set(); // dedupe identical chunk text within this lesson
    const entries = [];

    for (const fullText of explanationStrings) {
      const chunks = splitTextIntoChunks(fullText);
      for (const chunk of chunks) {
        if (seenChunks.has(chunk)) continue;
        seenChunks.add(chunk);

        const preview = chunk.length > 70 ? chunk.slice(0, 70) + "…" : chunk;
        if (DRY) {
          console.log(`  [dry] "${preview}"`);
          entries.push({ text: chunk, provider: "dry-run" });
          continue;
        }

        const audio = await renderChunk(chunk);
        console.log(`  provider=${audio.provider} cached=${audio.cached} "${preview}"`);
        if (audio.provider === "openai") sawOpenAI = true;
        if (!audio.cached && audio.provider !== "cache") sawLiveSynthesis = true;
        entries.push({ text: chunk, provider: audio.provider, cached: audio.cached });
      }
    }

    manifest.lessons[lesson.id] = { chunkCount: entries.length, entries };
  }

  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
  console.log(`\n[say-it-better] Wrote manifest: ${MANIFEST_PATH}`);

  if (!DRY) {
    if (sawOpenAI) {
      console.error("[say-it-better] ❌ RELEASE GATE FAILED — at least one clip was voiced by OpenAI. Do not ship until every clip is re-rendered and confirmed non-OpenAI.");
      process.exit(1);
    }
    console.log(sawLiveSynthesis
      ? "[say-it-better] All chunks rendered via Cloud TTS/Gemini (never OpenAI). Cache is now warm."
      : "[say-it-better] All chunks were already cached — nothing new to render."
    );
  }
  console.log("[say-it-better] done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

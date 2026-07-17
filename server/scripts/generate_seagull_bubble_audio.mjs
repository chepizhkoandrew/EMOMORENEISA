// Generate the Memorize-hub seagull (El Loro / "Seagull Steven") speech-bubble
// clips and write them as MP3s straight into the iOS Resources folder
// (auto-bundled via the Xcode synchronized group).
//
// Mirrors generate_dog_bubble_audio.mjs, but voices the seagull in a distinct
// OLD FEMALE voice — grandmotherly, warm, a touch raspy — so it is clearly a
// different character from the professor-dog (Gemini Charon). We use OpenAI
// gpt-4o-mini-tts because it accepts a free-text `instructions` field, which is
// the only way to steer the voice's *age* ("elderly woman") — Gemini prebuilt
// voices can't be aged.
//
// Each bubble is voiced as a short sequence: the Spanish phrase, then its
// meaning in the learner's language — spoken exactly once, no repeat:
//   Spanish phrase  →  native meaning
//
// Output files (4 phrases × 2 languages):
//   loro_bubble_<i>_en.mp3   ES + "English meaning"
//   loro_bubble_<i>_uk.mp3   ES + "Ukrainian meaning"
//
// The phrase table MUST stay in sync with `loroPhrases` in
// Memorize/Views/LoroMemorizeHubView.swift (es + English meaning) and the
// Ukrainian meanings in Localization/Strings_uk_Memorize.swift.
//
// Requirements: a working key in the shell env (or server/.env):
//   OPENAI_API_KEY=...
//
// Usage (from repo root or server/), with the Railway-sourced key:
//   railway run --service api node server/scripts/generate_seagull_bubble_audio.mjs
//   railway run --service api node server/scripts/generate_seagull_bubble_audio.mjs --lang=uk
//   railway run --service api node server/scripts/generate_seagull_bubble_audio.mjs --only=2 --force

import { spawn } from "node:child_process";
import { mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ffmpegPath from "ffmpeg-static";
import { config } from "../src/config.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const DEFAULT_OUT = join(REPO_ROOT, "EMOMORENEISA", "EMOMORENEISA", "EMOMORENEISA", "Resources");
const OUT_DIR = process.env.OUT_DIR || DEFAULT_OUT;

const SAMPLE_RATE = 24000; // OpenAI pcm response_format = s16le PCM @ 24kHz mono
const GAP_SECONDS = 0.32;

const args = process.argv.slice(2);
const ONLY_LANG = args.find((a) => a.startsWith("--lang="))?.split("=")[1];
const ONLY_INDEX = args.find((a) => a.startsWith("--only="))?.split("=")[1];
const FORCE = args.includes("--force"); // re-generate even if the mp3 exists

// The old-lady seagull voice. A female OpenAI voice + an explicit "elderly"
// instruction is what gives the grandmotherly character the dog voice lacks.
// The `instructions` field is honored ONLY by gpt-4o-mini-tts — the production
// MODEL_TTS_OPENAI ("tts-1") silently ignores it, so we pin the model here
// rather than reading config.models.ttsOpenAI.
const OPENAI_MODEL = process.env.SEAGULL_MODEL || "gpt-4o-mini-tts";
const OPENAI_VOICE = process.env.SEAGULL_VOICE || "shimmer";
const VOICE_INSTRUCTIONS =
  "Voice: an elderly woman — a warm, playful Spanish grandmother in her late " +
  "seventies. Slightly raspy and a little wavery with age, affectionate and " +
  "mischievous. Tone: unhurried and clear, with a gentle sing-song lilt, like " +
  "she's fondly teasing a grandchild.";

// Mirrors `loroPhrases` in Memorize/Views/LoroMemorizeHubView.swift (es +
// English meaning) and the uk meanings in Strings_uk_Memorize.swift.
const PHRASES = [
  { es: "La vida es loca", en: "Life is crazy", uk: "Життя божевільне" },
  { es: "Tenemos que trabajar", en: "We have to work", uk: "Треба робити роботу" },
  { es: "Ah, si-si o no?", en: "Ah, yes-yes or no?", uk: "Ой, та-так... чи ні?" },
  { es: "Huele a pollo?", en: "Smells like chicken?", uk: "Пахне куркою?" },
];

const LANGS = ONLY_LANG ? [ONLY_LANG] : ["en", "uk"];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const CALL_SPACING_MS = 400;
const MAX_ATTEMPTS = 6;

// Direct OpenAI TTS call so we can pass `voice` + `instructions` (the shared
// providers.openaiTTS helper hard-codes a single fallback voice with no
// instructions). Returns s16le PCM @ 24kHz mono.
async function openaiPcm(text) {
  const resp = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.openaiKey}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL, // gpt-4o-mini-tts (honors `instructions`)
      voice: OPENAI_VOICE,
      instructions: VOICE_INSTRUCTIONS,
      input: text,
      response_format: "pcm",
    }),
  });
  if (!resp.ok) {
    const detail = await resp.text().catch(() => "");
    const retryable = resp.status === 429 || resp.status >= 500;
    const err = new Error(`openai HTTP ${resp.status}: ${detail.slice(0, 200)}`);
    err.retryable = retryable;
    throw err;
  }
  return Buffer.from(await resp.arrayBuffer());
}

async function pcmFor(text) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const pcm = await openaiPcm(text);
      if (pcm && pcm.length > 0) {
        await sleep(CALL_SPACING_MS);
        return pcm;
      }
    } catch (e) {
      if (attempt === MAX_ATTEMPTS || e.retryable === false) throw e;
      const backoff = Math.min(30000, 2000 * 2 ** (attempt - 1));
      console.log(`    …retry ${attempt}/${MAX_ATTEMPTS - 1} for "${text}" in ${backoff}ms (${e.message})`);
      await sleep(backoff);
      continue;
    }
    throw new Error(`TTS returned empty audio for "${text}"`);
  }
}

function silence(seconds) {
  return Buffer.alloc(Math.round(SAMPLE_RATE * 2 * seconds)); // 16-bit mono
}

function pcmToMp3(pcm, outPath) {
  return new Promise((res, rej) => {
    if (!ffmpegPath) return rej(new Error("ffmpeg-static unavailable"));
    const ff = spawn(ffmpegPath, [
      "-y",
      "-f", "s16le", "-ar", String(SAMPLE_RATE), "-ac", "1", "-i", "pipe:0",
      "-codec:a", "libmp3lame", "-qscale:a", "3",
      outPath,
    ]);
    const err = [];
    ff.stderr.on("data", (d) => err.push(d));
    ff.on("close", (code) =>
      code === 0 ? res() : rej(new Error(`ffmpeg_${code}: ${Buffer.concat(err).toString().slice(-300)}`))
    );
    ff.stdin.on("error", () => {});
    ff.stdin.end(pcm);
  });
}

async function buildPhrase(index, phrase) {
  const targets = LANGS
    .filter((lang) => phrase[lang])
    .map((lang) => ({ lang, outPath: join(OUT_DIR, `loro_bubble_${index}_${lang}.mp3`) }))
    .filter(({ outPath }) => FORCE || !existsSync(outPath));
  if (targets.length === 0) {
    console.log(`  · [${index}] all variants present, skipping`);
    return;
  }

  const esPcm = await pcmFor(phrase.es);
  const gap = silence(GAP_SECONDS);

  for (const { lang, outPath } of targets) {
    const tail = phrase[lang];
    const nativePcm = await pcmFor(tail);
    const pcm = Buffer.concat([esPcm, gap, nativePcm]);
    await pcmToMp3(pcm, outPath);
    console.log(`  ✓ [${index}/${lang}] "${phrase.es}" → "${tail}"  ${outPath}`);
  }
}

async function main() {
  console.log(`Voice: OpenAI ${OPENAI_MODEL} / ${OPENAI_VOICE} (elderly woman)  Langs: ${LANGS.join(",")}  Out: ${OUT_DIR}`);
  if (!config.openaiKey) throw new Error("OPENAI_API_KEY is empty (use `railway run --service api`)");
  mkdirSync(OUT_DIR, { recursive: true });

  const entries = PHRASES.map((p, i) => [i, p]).filter(
    ([i]) => ONLY_INDEX == null || String(i) === ONLY_INDEX
  );
  for (const [i, phrase] of entries) {
    await buildPhrase(i, phrase);
  }
  console.log("Done.");
}

main().catch((e) => {
  console.error("FAILED:", e.message);
  process.exit(1);
});

// Generate the onboarding CTA voice lines ("¡Vamos a probar!" + a native tail)
// in the SAME voice engine the app uses, and write them as MP3s straight into
// the iOS Resources folder (auto-bundled via the Xcode synchronized group).
//
// Output files:
//   onboard_vamos_start_en.mp3   "¡Vamos a probar! Let's start!"
//   onboard_vamos_start_uk.mp3   "¡Vamos a probar! Розпочинаємо!"
//
// Requirements: a working key in server/.env (or the shell env):
//   GEMINI_API_KEY=...      (default engine — Charon, multilingual, one voice)
//   or OPENAI_API_KEY=...   (with --engine=openai — onyx fallback voice)
//   or Google Cloud creds   (with --engine=auto — prod pipeline / Chirp3-HD)
//
// Usage (from repo root or server/):
//   node server/scripts/generate_onboard_audio.mjs                 # single-shot, both langs
//   node server/scripts/generate_onboard_audio.mjs --glue          # glue ES clip + native tail
//   node server/scripts/generate_onboard_audio.mjs --lang=uk       # only Ukrainian
//   node server/scripts/generate_onboard_audio.mjs --engine=auto   # use prod synthesizeVoice()
//   OUT_DIR=/tmp/audio node server/scripts/generate_onboard_audio.mjs   # write elsewhere
//
// --glue exists for the case the single-shot mixed-language render sounds off
// (wrong accent on the tail): it voices the Spanish and the native part as
// separate calls, then stitches them with a short pause so each keeps its own
// natural pronunciation.

import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ffmpegPath from "ffmpeg-static";
import { config } from "../src/config.js";
import { synthesizeVoice, geminiTTS, openaiTTS } from "../src/providers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const DEFAULT_OUT = join(REPO_ROOT, "EMOMORENEISA", "EMOMORENEISA", "EMOMORENEISA", "Resources");
const OUT_DIR = process.env.OUT_DIR || DEFAULT_OUT;

const SAMPLE_RATE = 24000; // all engines emit s16le PCM @ 24kHz mono
const GAP_SECONDS = 0.28;

const args = process.argv.slice(2);
const GLUE = args.includes("--glue");
const ENGINE = (args.find((a) => a.startsWith("--engine="))?.split("=")[1]) || "gemini";
const ONLY_LANG = args.find((a) => a.startsWith("--lang="))?.split("=")[1];

// Spanish stem + per-language tail. The stem is identical everywhere; only the
// tail switches so the encouragement lands in the learner's own language.
const SPANISH_STEM = "¡Vamos a probar!";
const LANGS = {
  en: { file: "onboard_vamos_start_en.mp3", tail: "Let's start!" },
  uk: { file: "onboard_vamos_start_uk.mp3", tail: "Розпочинаємо!" },
};

function tts(text) {
  if (ENGINE === "gemini") return geminiTTS(text);
  if (ENGINE === "openai") return openaiTTS(text);
  if (ENGINE === "auto") return synthesizeVoice(text, { allowOpenAIFallback: true });
  throw new Error(`unknown --engine=${ENGINE} (use gemini | openai | auto)`);
}

async function pcmFor(text) {
  const audio = await tts(text);
  if (!audio?.audioBase64) {
    throw new Error(`TTS returned no audio for "${text}" (engine=${ENGINE}). Check the API key.`);
  }
  return Buffer.from(audio.audioBase64, "base64");
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

async function buildLang(code, { file, tail }) {
  let pcm;
  if (GLUE) {
    const [stem, native] = await Promise.all([pcmFor(SPANISH_STEM), pcmFor(tail)]);
    pcm = Buffer.concat([stem, silence(GAP_SECONDS), native]);
    console.log(`  [glue] ${code}: "${SPANISH_STEM}" + "${tail}"`);
  } else {
    pcm = await pcmFor(`${SPANISH_STEM} ${tail}`);
    console.log(`  [single] ${code}: "${SPANISH_STEM} ${tail}"`);
  }
  const outPath = join(OUT_DIR, file);
  await pcmToMp3(pcm, outPath);
  console.log(`  ✓ wrote ${outPath}`);
}

async function main() {
  console.log(`Engine: ${ENGINE}  Mode: ${GLUE ? "glue" : "single"}  Out: ${OUT_DIR}`);
  if (ENGINE === "gemini" && !config.geminiKey) throw new Error("GEMINI_API_KEY is empty (set it in server/.env)");
  if (ENGINE === "openai" && !config.openaiKey) throw new Error("OPENAI_API_KEY is empty (set it in server/.env)");
  mkdirSync(OUT_DIR, { recursive: true });

  const entries = Object.entries(LANGS).filter(([code]) => !ONLY_LANG || code === ONLY_LANG);
  for (const [code, spec] of entries) {
    await buildLang(code, spec);
  }
  console.log("Done.");
}

main().catch((e) => {
  console.error("FAILED:", e.message);
  process.exit(1);
});

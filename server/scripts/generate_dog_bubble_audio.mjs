// Generate the home professor-dog speech-bubble clips in the SAME voice engine
// the app uses, and write them as MP3s straight into the iOS Resources folder
// (auto-bundled via the Xcode synchronized group).
//
// Each bubble is voiced as a short sequence so the learner hears the Spanish,
// then its meaning in their own language — spoken exactly once, no repeat:
//   Spanish phrase  →  native meaning
//
// Output files (10 phrases × 2 languages):
//   dog_bubble_<i>_en.mp3   ES + "English meaning"
//   dog_bubble_<i>_uk.mp3   ES + "Ukrainian meaning"
//
// Requirements: a working key in the shell env (or server/.env):
//   GEMINI_API_KEY=...   (default engine — Charon, multilingual, one voice)
//
// Usage (from repo root or server/), with the Railway-sourced key:
//   railway run node server/scripts/generate_dog_bubble_audio.mjs
//   railway run node server/scripts/generate_dog_bubble_audio.mjs --lang=uk
//   railway run node server/scripts/generate_dog_bubble_audio.mjs --only=6
//   OUT_DIR=/tmp/audio railway run node server/scripts/generate_dog_bubble_audio.mjs
//
// The same Spanish voice reads the English/Ukrainian meaning too — an accent on
// the native line is expected and acceptable.

import { spawn } from "node:child_process";
import { mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ffmpegPath from "ffmpeg-static";
import { config } from "../src/config.js";
import { geminiTTS, openaiTTS, synthesizeVoice } from "../src/providers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const DEFAULT_OUT = join(REPO_ROOT, "EMOMORENEISA", "EMOMORENEISA", "EMOMORENEISA", "Resources");
const OUT_DIR = process.env.OUT_DIR || DEFAULT_OUT;

const SAMPLE_RATE = 24000; // all engines emit s16le PCM @ 24kHz mono
const GAP_SECONDS = 0.32;

const args = process.argv.slice(2);
const ENGINE = args.find((a) => a.startsWith("--engine="))?.split("=")[1] || "gemini";
const ONLY_LANG = args.find((a) => a.startsWith("--lang="))?.split("=")[1];
const ONLY_INDEX = args.find((a) => a.startsWith("--only="))?.split("=")[1];
const FORCE = args.includes("--force"); // re-generate even if the mp3 exists

// Mirrors the phrase table in Home/ModeSelectorView.swift (es) and the meaning
// values in Localization/Strings_uk_Home.swift (uk). English meaning == the
// Swift `meaning` string, which is also the L() lookup key.
const PHRASES = [
  { es: "¡Soy Proffesssorrro!", en: "I'm the Proffessorrr!", uk: "Я — Професоррр!" },
  { es: "Vamos a ensenar me", en: "Let's teach… me!", uk: "Ану навчімо… мене!" },
  { es: "no puedo esperar mas", en: "I can't wait any longer", uk: "Більше не можу чекати" },
  { es: "comida buena", en: "Good food", uk: "Смачна їжа" },
  { es: "vivo en momento", en: "I live in the moment", uk: "Живу цією миттю" },
  { es: "Todo es caro", en: "Everything's expensive", uk: "Усе дороге" },
  { es: "Hola bichito", en: "Hey, creature", uk: "Привіт, звірятко!" },
  { es: "Fu! Deja lo!!!", en: "Ugh! Drop it!!!", uk: "Фу! Кинь це!!!" },
  { es: "Vamos a la playa", en: "Let's go to the beach", uk: "Гайда на пляж" },
  { es: "Es un cabrón y narcisista! Como yo.", en: "He's a jerk and a narcissist! Like me.", uk: "Він козел і нарцис! Як я." },
];

const LANGS = ONLY_LANG ? [ONLY_LANG] : ["en", "uk"];

function tts(text) {
  if (ENGINE === "gemini") return geminiTTS(text);
  if (ENGINE === "openai") return openaiTTS(text);
  if (ENGINE === "auto") return synthesizeVoice(text, { allowOpenAIFallback: true });
  throw new Error(`unknown --engine=${ENGINE} (use gemini | openai | auto)`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Gentle base spacing between calls plus exponential backoff on failure keeps
// us under the Gemini TTS free-tier rate/quota limit (bursting 30 calls trips
// HTTP 429).
const CALL_SPACING_MS = 1800;
const MAX_ATTEMPTS = 7;

async function pcmFor(text) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    let audio = null;
    try {
      audio = await tts(text);
    } catch {
      audio = null;
    }
    if (audio?.audioBase64) {
      await sleep(CALL_SPACING_MS);
      return Buffer.from(audio.audioBase64, "base64");
    }
    if (attempt === MAX_ATTEMPTS) {
      throw new Error(`TTS returned no audio for "${text}" (engine=${ENGINE}) after ${MAX_ATTEMPTS} attempts.`);
    }
    const backoff = Math.min(30000, 2000 * 2 ** (attempt - 1));
    console.log(`    …retry ${attempt}/${MAX_ATTEMPTS - 1} for "${text}" in ${backoff}ms`);
    await sleep(backoff);
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
  // Skip whole phrase if every language variant already exists (resume).
  const targets = LANGS
    .filter((lang) => phrase[lang])
    .map((lang) => ({ lang, outPath: join(OUT_DIR, `dog_bubble_${index}_${lang}.mp3`) }))
    .filter(({ outPath }) => FORCE || !existsSync(outPath));
  if (targets.length === 0) {
    console.log(`  · [${index}] all variants present, skipping`);
    return;
  }

  // Voice the Spanish once, then follow it with the native meaning — no repeat.
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
  console.log(`Engine: ${ENGINE}  Langs: ${LANGS.join(",")}  Out: ${OUT_DIR}`);
  if (ENGINE === "gemini" && !config.geminiKey) throw new Error("GEMINI_API_KEY is empty (set it in server/.env or use `railway run`)");
  if (ENGINE === "openai" && !config.openaiKey) throw new Error("OPENAI_API_KEY is empty");
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

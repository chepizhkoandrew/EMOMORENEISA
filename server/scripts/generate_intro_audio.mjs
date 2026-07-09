// Generate the onboarding-carousel narration clips and write them as MP3s
// straight into the iOS Resources folder (auto-bundled via the Xcode
// synchronized group).
//
// Unlike the dog/explore bubble clips (Spanish phrase → native meaning), the
// intro narration is native-only — the whole line is spoken in the user's own
// language, no Spanish transcription. To keep the professor's voice consistent
// across languages we request the SAME Chirp 3 HD voice name (Achird) in the
// matching locale (uk-UA / en-US), so it sounds like one narrator, not three.
//
// Output files:
//   onboard_intro_<lang>.mp3            full dog-slide narration
//   onboard_head_streetview_<lang>.mp3  slide 1 header
//   onboard_head_consistency_<lang>.mp3 slide 2 header
//   onboard_head_verbs_<lang>.mp3       slide 3 header
//
// Usage (from repo root or server/), with the Railway-sourced credentials:
//   railway run --service api node scripts/generate_intro_audio.mjs
//   railway run --service api node scripts/generate_intro_audio.mjs --lang=uk
//   railway run --service api node scripts/generate_intro_audio.mjs --only=onboard_intro --force

import { spawn } from "node:child_process";
import { mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ffmpegPath from "ffmpeg-static";
import { config } from "../src/config.js";
import { synthesizeVoice } from "../src/providers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const DEFAULT_OUT = join(REPO_ROOT, "EMOMORENEISA", "EMOMORENEISA", "EMOMORENEISA", "Resources");
const OUT_DIR = process.env.OUT_DIR || DEFAULT_OUT;

const SAMPLE_RATE = 24000; // Cloud TTS emits s16le PCM @ 24kHz mono

const args = process.argv.slice(2);
const ONLY_LANG = args.find((a) => a.startsWith("--lang="))?.split("=")[1];
const ONLY_ID = args.find((a) => a.startsWith("--only="))?.split("=")[1];
const FORCE = args.includes("--force");

const LANGS = ONLY_LANG ? [ONLY_LANG] : ["en", "uk"];

// Same Chirp 3 HD voice name as the Spanish (es-ES-Chirp3-HD-Achird), but in
// each native locale, so the narrator's timbre stays consistent everywhere.
const VOICE = {
  en: { languageCode: "en-US", voiceName: "en-US-Chirp3-HD-Achird" },
  uk: { languageCode: "uk-UA", voiceName: "uk-UA-Chirp3-HD-Achird" },
};

// TTS-friendly text (single periods, lowercase words, spelled numerals handled
// by the engine). Mirrors the on-screen copy in Views/Intro/OnboardingCarouselView.swift
// (dog slide) and the meanings in Localization/Strings_uk_Intro.swift.
const CLIPS = [
  {
    id: "onboard_intro",
    context: "sentence",
    en: "This is the app for learning Spanish. It uses dog training techniques. Gauwau! And NLP techniques for better remembering. Created by human.",
    uk: "Це додаток для вивчення іспанської. Він використовує собачі техніки дресури. Гав-вау! А ще НЛП-техніки для кращого запам’ятовування. Створено людиною.",
  },
  {
    id: "onboard_head_streetview",
    context: "default",
    en: "Street view. Learn anywhere.",
    uk: "Візуалізація. Вчи те, що бачиш навколо.",
  },
  {
    id: "onboard_head_consistency",
    context: "default",
    en: "Consistency is the trick.",
    uk: "Регулярність. Ось увесь секрет.",
  },
  {
    id: "onboard_head_verbs",
    context: "default",
    en: "Verbs and times is 80% of Spanish.",
    uk: "Дієслова й часи — це 80% іспанської.",
  },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const CALL_SPACING_MS = 400;
const MAX_ATTEMPTS = 5;

async function pcmFor(text, context, lang) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    let audio = null;
    try {
      audio = await synthesizeVoice(text, { context, voiceOverride: VOICE[lang] });
    } catch {
      audio = null;
    }
    if (audio?.audioBase64) {
      await sleep(CALL_SPACING_MS);
      return Buffer.from(audio.audioBase64, "base64");
    }
    if (attempt === MAX_ATTEMPTS) {
      throw new Error(`TTS returned no audio for "${text}" (lang=${lang}) after ${MAX_ATTEMPTS} attempts.`);
    }
    const backoff = Math.min(30000, 2000 * 2 ** (attempt - 1));
    console.log(`    …retry ${attempt}/${MAX_ATTEMPTS - 1} for "${text}" in ${backoff}ms`);
    await sleep(backoff);
  }
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

async function buildClip(clip) {
  for (const lang of LANGS) {
    const text = clip[lang];
    if (!text) continue;
    const outPath = join(OUT_DIR, `${clip.id}_${lang}.mp3`);
    if (!FORCE && existsSync(outPath)) {
      console.log(`  · [${clip.id}/${lang}] present, skipping`);
      continue;
    }
    const pcm = await pcmFor(text, clip.context, lang);
    await pcmToMp3(pcm, outPath);
    console.log(`  ✓ [${clip.id}/${lang}] "${text}"  ${outPath}`);
  }
}

async function main() {
  console.log(`Langs: ${LANGS.join(",")}  Out: ${OUT_DIR}`);
  if (!config.cloudTts.enabled) {
    throw new Error("Cloud TTS is not enabled (GOOGLE_TTS_CREDENTIALS missing — use `railway run`).");
  }
  mkdirSync(OUT_DIR, { recursive: true });

  const clips = CLIPS.filter((c) => ONLY_ID == null || c.id === ONLY_ID);
  for (const clip of clips) {
    await buildClip(clip);
  }
  console.log("Done.");
}

main().catch((e) => {
  console.error("FAILED:", e.message);
  process.exit(1);
});

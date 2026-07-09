// Pre-renders the 11 pre-recorded onboarding voice lines (9 questions
// Q1..Q7 + Q10 + Q11 + reprompt + fallback) × {en/neutral, uk/he, uk/she, uk/they}
// as AAC via the app's own TTS pipeline (Google Cloud Chirp 3 HD → Gemini
// Charon → OpenAI fallback), pinned to the SAME activeVoiceTag() the app uses
// at runtime. Dedupes identical bytes across gender variants into shared_/
// symlinks so the bundle doesn't ship the same audio 3×.
//
// Output layout (relative to Onboarding/Assets/):
//   en/neutral/q1.aac ... q7.aac, q10.aac, q11.aac, reprompt.aac, fallback.aac
//   en/neutral/manifest.json
//   uk/he/... uk/she/... uk/they/... same shape
//   shared_/<sha>.aac (content-addressed dedupe target)
//
// Usage:
//   node server/scripts/render-onboarding-assets.js
//   node server/scripts/render-onboarding-assets.js --lang=uk --gender=they
//   node server/scripts/render-onboarding-assets.js --dry
//
// Requires the same env as the running proxy (GEMINI_API_KEY, and/or Google
// Cloud service account for Chirp3 HD).

import crypto from "node:crypto";
import { writeFileSync, mkdirSync, existsSync, symlinkSync, unlinkSync, statSync } from "node:fs";
import { dirname, join, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { getVoice, activeVoiceTag } from "../src/voicecache.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const OUT_DIR = join(REPO_ROOT, "EMOMORENEISA", "EMOMORENEISA", "EMOMORENEISA", "Onboarding", "Assets");

// -----------------------------------------------------------------------------
// Question bank — v1.3. Must stay 1:1 with iOS OnboardingQuestionBank.swift.
// EN has ONE variant (English 2nd person is genderless). UK has 3 variants;
// gender-neutral lines are marked with `neutral: true` and rendered once for
// he and then symlinked for she / they at render time.
// -----------------------------------------------------------------------------

const BANK = {
  en: {
    neutral: {
      q1:  "So — what should I call you, and what country and city are you in these days?",
      q2:  "What do you do in life — working, studying, raising kids?",
      q3:  "Why do you want to learn Spanish? For work? To connect with people — with anyone in particular? Or just for fun, or for school?",
      q4:  "How long have you been learning Spanish? Do you go to a school, use other apps, or are you just starting out and not sure where to begin?",
      q5:  "How would you rate your Spanish right now — your listening, your speaking, and your reading, each on its own?",
      q5b: "And what would you like to improve most — learning new words and grammar, or speaking without fear?",
      q6:  "Tell me one sentence about your daily routine — what do you do in the morning, do you live alone or with someone, where do you work, and what do you like doing in your free time?",
      q7:  "Tell me one small, totally random thing about yourself — a pet, a weird hobby, your best friend's name — whatever pops into your head first.",
      q10: "Imagine you already speak Spanish fluently — what changes in your life?",
      q11: "And the last one — the hardest. Listen carefully and don't take it the wrong way… who do you like more, dogs or cats? Dogs, right? Tell me you like dogs more.",
      reprompt: "One more time? I didn't quite catch that.",
      fallback: "Tell me one small, totally random thing about yourself — a pet, a weird hobby, your best friend's name — whatever pops into your head first."
    }
  },
  uk: {
    he: {
      q1:  "То як тебе звати, і в якій країні та місті ти зараз живеш?",
      q2:  "Чим ти займаєшся в житті — працюєш, вчишся, ростиш дітей?",
      q3:  "Чому ти хочеш вивчити іспанську? Для роботи? Щоб спілкуватися з людьми — з кимось конкретно? Чи просто для задоволення, чи для навчання?",
      q4:  "Як довго ти вчиш іспанську? Ходиш до школи, користуєшся іншими додатками, чи це самий початок і ти ще не знаєш, з чого стартувати?",
      q5:  "Як ти оцінюєш свою іспанську зараз — окремо аудіювання, говоріння і читання, кожне саме по собі?",
      q5b: "А що ти хотів би покращити найбільше — вивчити нові слова й граматику, чи почати говорити без страху?",
      q6:  "Розкажи одним реченням про свій звичайний день — що робиш зранку, живеш сам чи з кимось, де працюєш і чим любиш займатися у вільний час?",
      q7:  "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращого друга — що першим спаде на думку.",
      q10: "Уяви, що ти вже вільно говориш іспанською — що зміниться у твоєму житті?",
      q11: "І останнє — найскладніше. Слухай уважно і не зрозумій мене неправильно… кого ти любиш більше, собак чи котів? Собак, правда ж? Скажи, що любиш собак більше.",
      reprompt: "Ще раз? Я не зовсім розчув.",
      fallback: "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращого друга — що першим спаде на думку."
    },
    she: {
      q1:  "То як тебе звати, і в якій країні та місті ти зараз живеш?",       // neutral
      q2:  "Чим ти займаєшся в житті — працюєш, вчишся, ростиш дітей?",       // neutral
      q3:  "Чому ти хочеш вивчити іспанську? Для роботи? Щоб спілкуватися з людьми — з кимось конкретно? Чи просто для задоволення, чи для навчання?", // neutral
      q4:  "Як довго ти вчиш іспанську? Ходиш до школи, користуєшся іншими додатками, чи це самий початок і ти ще не знаєш, з чого стартувати?",       // neutral
      q5:  "Як ти оцінюєш свою іспанську зараз — окремо аудіювання, говоріння і читання, кожне саме по собі?", // neutral
      q5b: "А що ти хотіла б покращити найбільше — вивчити нові слова й граматику, чи почати говорити без страху?",
      q6:  "Розкажи одним реченням про свій звичайний день — що робиш зранку, живеш сама чи з кимось, де працюєш і чим любиш займатися у вільний час?",
      q7:  "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращої подруги — що першим спаде на думку.",
      q10: "Уяви, що ти вже вільно говориш іспанською — що зміниться у твоєму житті?", // neutral
      q11: "І останнє — найскладніше. Слухай уважно і не зрозумій мене неправильно… кого ти любиш більше, собак чи котів? Собак, правда ж? Скажи, що любиш собак більше.", // neutral
      reprompt: "Ще раз? Я не зовсім розчула.",
      fallback: "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращої подруги — що першим спаде на думку."
    },
    they: {
      q1:  "То як тебе звати, і в якій країні та місті ти зараз живеш?",       // neutral (present tense, no gendered endings)
      q2:  "Чим ти займаєшся в житті — працюєш, вчишся, ростиш дітей?",       // neutral
      q3:  "Чому ти хочеш вивчити іспанську? Для роботи? Щоб спілкуватися з людьми — з кимось конкретно? Чи просто для задоволення, чи для навчання?", // neutral
      q4:  "Як довго ти вчиш іспанську? Ходиш до школи, користуєшся іншими додатками, чи це самий початок і ти ще не знаєш, з чого стартувати?",       // neutral
      q5:  "Як ти оцінюєш свою іспанську зараз — окремо аудіювання, говоріння і читання, кожне саме по собі?", // neutral
      q5b: "А що хочеться покращити найбільше — вивчити нові слова й граматику, чи почати говорити без страху?",
      q6:  "Розкажи одним реченням про свій звичайний день — що робиш зранку, живеш одне чи з кимось, де працюєш і чим любиш займатися у вільний час?",
      q7:  "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращого друга — що першим спаде на думку.",
      q10: "Уяви, що ти вже вільно говориш іспанською — що зміниться у твоєму житті?", // neutral
      q11: "І останнє — найскладніше. Слухай уважно і не зрозумій мене неправильно… кого ти любиш більше, собак чи котів? Собак, правда ж? Скажи, що любиш собак більше.", // neutral
      reprompt: "Ще раз? Я не зовсім розчув тебе.",
      fallback: "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращого друга — що першим спаде на думку."
    }
  }
};

const SLOTS = ["q1","q2","q3","q4","q5","q5b","q6","q7","q10","q11","reprompt","fallback"];

const args = process.argv.slice(2);
const DRY = args.includes("--dry");
const ONLY_LANG = args.find(a => a.startsWith("--lang="))?.split("=")[1];
const ONLY_GENDER = args.find(a => a.startsWith("--gender="))?.split("=")[1];

function sha(buf) { return crypto.createHash("sha256").update(buf).digest("hex").slice(0, 32); }

async function renderText(text) {
  const audio = await getVoice(text, { format: "aac", context: "sentence" });
  if (!audio || !audio.audioBase64) throw new Error("tts_failed");
  return Buffer.from(audio.audioBase64, "base64");
}

async function main() {
  const voiceTag = activeVoiceTag();
  console.log(`[render-onboarding] Voice tag: ${voiceTag}`);
  console.log(`[render-onboarding] Output:    ${OUT_DIR}`);
  if (DRY) console.log("[render-onboarding] DRY RUN — will print plan only");

  mkdirSync(join(OUT_DIR, "shared_"), { recursive: true });

  const languages = ONLY_LANG ? [ONLY_LANG] : Object.keys(BANK);
  for (const lang of languages) {
    const genders = ONLY_GENDER ? [ONLY_GENDER] : Object.keys(BANK[lang]);
    for (const gender of genders) {
      if (!BANK[lang][gender]) {
        console.warn(`[render-onboarding] skip ${lang}/${gender} — not in bank`);
        continue;
      }
      const dir = join(OUT_DIR, lang, gender);
      mkdirSync(dir, { recursive: true });
      const manifest = { lang, gender, voiceTag, slots: {} };

      for (const slot of SLOTS) {
        const text = BANK[lang][gender][slot];
        if (!text) throw new Error(`missing ${lang}/${gender}/${slot}`);
        const outPath = join(dir, `${slot}.aac`);
        console.log(`  ${lang}/${gender}/${slot}: ${text.slice(0, 60)}${text.length > 60 ? "…" : ""}`);
        if (DRY) { manifest.slots[slot] = { path: `${slot}.aac`, sha: "dry" }; continue; }

        const buf = await renderText(text);
        const hash = sha(buf);
        const sharedPath = join(OUT_DIR, "shared_", `${hash}.aac`);
        if (!existsSync(sharedPath)) writeFileSync(sharedPath, buf);
        try { if (existsSync(outPath)) unlinkSync(outPath); } catch (_) {}
        const rel = relative(dir, sharedPath);
        try { symlinkSync(rel, outPath); }
        catch (_) { writeFileSync(outPath, buf); }
        manifest.slots[slot] = { path: `${slot}.aac`, sha: hash, bytes: buf.length };
      }
      writeFileSync(join(dir, "manifest.json"), JSON.stringify(manifest, null, 2));
      console.log(`  → wrote manifest ${lang}/${gender}/manifest.json`);
    }
  }
  console.log("[render-onboarding] done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

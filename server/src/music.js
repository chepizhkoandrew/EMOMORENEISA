import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import { geminiText } from "./providers.js";

// Song generation pipeline. The proxy composes learner-friendly Spanish lyrics
// (Gemini) when the client didn't supply explicit ones, then calls the
// self-hosted ACE-Step service (Modal, GPU, scale-to-zero) to render audio.
// Generation takes 10s–3min (cold starts load the model), so it runs as an
// async job the client polls — a single long HTTP request would sail past
// mobile network timeouts.
//
// (Originally deployed on Cloud Run; its GPU-attached containers never
// reliably received external traffic — healthy container, zero requests ever
// routed to it, reproduced across regions/frameworks/configs. Moved to Modal,
// which owns its own web-serving layer instead of us managing one.)

// In-memory job store. Fine for the current single-process Railway deployment
// and the testing phase; revisit (Supabase table) before scaling out.
const jobs = new Map();
const JOB_TTL_MS = 30 * 60 * 1000;

function pruneJobs() {
  const now = Date.now();
  for (const [id, job] of jobs) {
    if (now - job.createdAt > JOB_TTL_MS) jobs.delete(id);
  }
}

export function getMusicJob(id, userId) {
  pruneJobs();
  const job = jobs.get(id);
  if (!job || job.userId !== userId) return null;
  return job;
}

export function musicConfigured() {
  return Boolean(config.music.serviceUrl);
}

// ACE-Step reads structure markers like [verse]/[chorus] in the lyrics and a
// comma-separated style tag list as the prompt. Ask Gemini for both at once.
function lyricsPrompt({ genre, description, words, durationSec, language }) {
  const wordList = (words || []).filter(Boolean).join(", ");
  const langName = language === "uk" ? "Ukrainian" : "English";
  return `You are a songwriter for a Spanish-learning app. Write song lyrics that help a learner remember Spanish vocabulary.

Genre: ${genre}
Song length: ${durationSec} seconds (keep lyrics short enough to be sung in that time).
${description ? `What the user wants the song to be about: ${description}` : ""}
${wordList ? `Spanish words/phrases from the user's memory queue that MUST each appear at least once, sung clearly: ${wordList}` : ""}

Rules:
- Lyrics are mostly Spanish, simple A1-A2 level, catchy and repetitive (repetition helps memory).
- If a required word is obscure, build a memorable hook around it.
- Use structure markers on their own lines: [verse], [chorus], [bridge], [outro]. For a ${durationSec}s song use ${durationSec <= 30 ? "one short verse and one chorus" : durationSec <= 60 ? "two verses and a repeated chorus" : "two-three verses, chorus repeats, and a bridge"}.
- Also produce a short song title in Spanish and a comma-separated list of 4-8 music style tags describing the genre for a music model (e.g. "reggaeton, latin, upbeat, male vocals, 100 bpm, catchy").

Answer in JSON only: {"title": "...", "styleTags": "...", "lyrics": "..."} (lyrics with \\n line breaks). The title and styleTags are in ${langName === "Ukrainian" ? "Spanish (title) and English (tags)" : "Spanish (title) and English (tags)"}.`;
}

// --- Karaoke timings ---------------------------------------------------------

// Lines that are actually sung: no blanks, no [verse]/[chorus] markers.
function sungLines(lyrics) {
  return lyrics
    .split("\n")
    .map(l => l.trim())
    .filter(l => l && !(l.startsWith("[") && l.endsWith("]")));
}

// Fallback when the music service returned no whisper alignment: spread the
// sung lines over the song, weighted by line length, leaving room for an
// instrumental intro/outro. Rough, but keeps karaoke usable.
function heuristicLineTimings(lyrics, durationSec) {
  const lines = sungLines(lyrics);
  if (!lines.length) return [];
  const intro = durationSec <= 30 ? 1.5 : 4;
  const outro = durationSec <= 30 ? 1 : 3;
  const singable = Math.max(1, durationSec - intro - outro);
  const weights = lines.map(l => Math.max(1, l.length));
  const total = weights.reduce((a, b) => a + b, 0);
  let t = intro;
  return lines.map((text, i) => {
    const span = singable * (weights[i] / total);
    const line = { text, startSec: Math.round(t * 100) / 100, endSec: Math.round((t + span) * 100) / 100 };
    t += span;
    return line;
  });
}

// --- Picture plan (karaoke slideshow) ----------------------------------------

// Up to 5 pictures for a 30s song, 10 for a minute, a few more for two.
function sceneCap(durationSec) {
  if (durationSec <= 30) return 5;
  if (durationSec <= 60) return 10;
  return 14;
}

// Floor so a short/lazy scene plan doesn't leave a 30s clip with just 1-2
// pictures — clamped against how many lines actually exist, since a scene
// needs at least one distinct line range (a plan can't invent more scenes
// than there are lines to assign them to).
function sceneMin(durationSec, lineCount) {
  const target = durationSec <= 30 ? 3 : durationSec <= 60 ? 5 : 7;
  return Math.max(1, Math.min(target, lineCount));
}

function scenePlanPrompt({ lines, words, durationSec }) {
  const numbered = lines.map((l, i) => `${i}: ${l}`).join("\n");
  const wordList = (words || []).filter(Boolean).join(", ");
  const min = sceneMin(durationSec, lines.length);
  return `You plan the picture slideshow for a karaoke video of a Spanish-learning song. Each scene covers a contiguous range of lyric lines and shows ONE picture illustrating what those lines are about.

Sung lyric lines (numbered):
${numbered}

${wordList ? `Spanish words/phrases from the learner's memory queue (they already have a picture for each): ${wordList}` : "The learner selected no memory-queue words."}

Rules:
- Between ${min} and ${sceneCap(durationSec)} scenes (never fewer than ${min} unless there are literally fewer than ${min} lyric lines total), in order, covering ALL lines from first to last with no gaps (scene N+1 starts on the line after scene N ends). Do not lazily cover the whole song in one or two scenes — break it up so the picture actually changes as the song progresses.
- When a range of lines features one of the memory-queue words, set "word" to that word EXACTLY as given above; otherwise "word" is "".
- Every scene also gets a "spanish" phrase (2-6 words) naming the concrete thing to draw and an "english" translation. When "word" is set, "spanish" is centred on that word.
- When the song returns to the same subject (e.g. a repeated chorus), REUSE the identical spanish+english pair so the same picture reappears.

Answer in JSON only: {"scenes":[{"fromLine":0,"toLine":2,"word":"","spanish":"...","english":"..."}]}`;
}

// Best-effort storyboard: Gemini maps lyric lines to scenes; on failure the
// selected queue words become evenly-spread scenes (their pictures already
// exist client-side), and with no words the karaoke simply has no slideshow.
async function composeScenePlan({ lyrics, words, durationSec }) {
  const lines = sungLines(lyrics);
  if (!lines.length) return null;
  const r = await geminiText({
    prompt: scenePlanPrompt({ lines, words, durationSec }),
    model: config.music.lyricsModel,
    temperature: 0.4,
    maxOutputTokens: 2048
  });
  const cleaned = r.text.trim().replace(/```json/g, "").replace(/```/g, "").trim();
  const obj = JSON.parse(cleaned);
  if (!Array.isArray(obj.scenes) || !obj.scenes.length) return null;
  return obj.scenes
    .map(s => ({
      fromLine: Math.max(0, Math.min(lines.length - 1, Number(s.fromLine) || 0)),
      toLine: Math.max(0, Math.min(lines.length - 1, Number(s.toLine) || 0)),
      word: typeof s.word === "string" ? s.word.trim() : "",
      spanish: typeof s.spanish === "string" ? s.spanish.trim() : "",
      english: typeof s.english === "string" ? s.english.trim() : ""
    }))
    .filter(s => s.spanish)
    .slice(0, sceneCap(durationSec));
}

// Resolves with `fallback` if `promise` hasn't settled within `ms` — used so
// the post-audio scene-plan wait can never silently stretch the job past when
// the song itself is actually ready (composeScenePlan's Gemini call has no
// timeout of its own; a slow/rate-limited response would otherwise leave the
// client staring at "generating" long after the audio finished).
function withTimeout(promise, ms, fallback) {
  return new Promise(resolve => {
    const timer = setTimeout(() => resolve(fallback), ms);
    promise.then(v => { clearTimeout(timer); resolve(v); });
  });
}

function fallbackScenes(words, durationSec) {
  const clean = (words || []).filter(Boolean).slice(0, sceneCap(durationSec));
  if (!clean.length) return [];
  const span = durationSec / clean.length;
  return clean.map((word, i) => ({
    startSec: Math.round(i * span * 100) / 100,
    endSec: Math.round((i + 1) * span * 100) / 100,
    word,
    spanish: word,
    english: ""
  }));
}

// Line ranges -> seconds (using whichever line timings we ended up with), then
// stretched into a continuous slideshow: first scene from 0, last to the end,
// each scene running until the next begins.
function resolveScenes(planned, lines, durationSec, words) {
  if (!planned || !planned.length || !lines.length) return fallbackScenes(words, durationSec);
  const scenes = planned
    .map(s => ({
      startSec: lines[Math.min(s.fromLine, lines.length - 1)].startSec,
      endSec: lines[Math.min(s.toLine, lines.length - 1)].endSec,
      word: s.word,
      spanish: s.spanish,
      english: s.english
    }))
    .sort((a, b) => a.startSec - b.startSec);
  scenes[0].startSec = 0;
  for (let i = 0; i < scenes.length - 1; i++) scenes[i].endSec = scenes[i + 1].startSec;
  scenes[scenes.length - 1].endSec = durationSec;
  return scenes.filter(s => s.endSec > s.startSec);
}

function parseLyricsResponse(text, genre) {
  const cleaned = text.trim().replace(/```json/g, "").replace(/```/g, "").trim();
  const obj = JSON.parse(cleaned);
  if (!obj.lyrics) throw new Error("lyrics_compose_incomplete");
  return {
    title: String(obj.title || "Mi canción"),
    styleTags: String(obj.styleTags || genre),
    lyrics: String(obj.lyrics)
  };
}

// This is the ONE Gemini call that blocks the start of every song job (the
// "writing_lyrics" stage) — a malformed or truncated response here used to
// fail the whole job outright with zero retry, unlike the onboarding probe's
// established pattern of one retry at lower temperature. Mirrors that here.
async function composeLyrics(params) {
  const prompt = lyricsPrompt(params);
  const r = await geminiText({ prompt, model: config.music.lyricsModel, temperature: 0.8, maxOutputTokens: 2048 });
  try {
    return parseLyricsResponse(r.text, params.genre);
  } catch (_) {
    const retry = await geminiText({ prompt, model: config.music.lyricsModel, temperature: 0.3, maxOutputTokens: 2048 });
    return parseLyricsResponse(retry.text, params.genre);
  }
}

// Modal's web endpoint blocks on the underlying GPU call up to its own
// internal deadline (~150s observed); past that it returns 303 with a
// Location header pointing at a poll URL that re-runs the same wait. We
// drive that loop explicitly (redirect: "manual") rather than relying on
// fetch's built-in redirect-following, so we control the retry cadence and
// get a clear error if it chains further than expected.
async function callMusicService({ styleTags, lyrics, durationSec }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.music.requestTimeoutMs);
  try {
    let resp = await fetch(`${config.music.serviceUrl.replace(/\/$/, "")}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-API-Key": config.music.serviceKey
      },
      body: JSON.stringify({
        prompt: styleTags,
        lyrics,
        duration_sec: durationSec
      }),
      redirect: "manual",
      signal: controller.signal
    });

    let hops = 0;
    while (resp.status === 303 && hops < 20) {
      const location = resp.headers.get("location");
      if (!location) throw new Error("music_service_303_missing_location");
      resp = await fetch(location, { headers: { "X-API-Key": config.music.serviceKey }, redirect: "manual", signal: controller.signal });
      hops += 1;
    }

    if (!resp.ok) {
      let detail = "";
      try { detail = (await resp.text()).slice(0, 300); } catch (_) {}
      throw new Error(`music_service_${resp.status}: ${detail}`);
    }
    const json = await resp.json();
    if (!json.audioBase64) throw new Error("music_service_empty_audio");
    return {
      audioBase64: json.audioBase64,
      mime: json.mime || "audio/mpeg",
      lines: Array.isArray(json.lines) ? json.lines : []
    };
  } finally {
    clearTimeout(timer);
  }
}

// `onOutcome` (index.js) does real I/O — a wallet refund or a meter write —
// which can itself fail (e.g. a transient Supabase error). It used to be
// called fire-and-forget with no await/catch anywhere in the chain: an
// unhandled promise rejection in it crashed the ENTIRE process (confirmed —
// Node 20+ kills the process on any unhandled rejection by default), taking
// every other in-flight request down with it and wiping the logs on the
// following restart, which is exactly why a failed song render looked
// unexplainable after the fact. A job outcome must never be able to do that.
async function runOutcome(onOutcome, outcome, jobId) {
  try {
    await onOutcome?.(outcome);
  } catch (e) {
    console.error(`[music] job ${jobId} onOutcome handler itself failed:`, e.message);
  }
}

// Creates the job and runs the pipeline in the background. `onOutcome` fires
// exactly once with { ok } so the route can refund treats on failure.
export function startMusicJob({ userId, genre, durationSec, lyrics, description, words, language }, onOutcome) {
  pruneJobs();
  const id = randomUUID();
  const job = {
    id,
    userId,
    status: "queued", // queued -> writing_lyrics -> generating -> done | failed
    createdAt: Date.now(),
    genre,
    durationSec,
    error: null,
    song: null
  };
  jobs.set(id, job);

  // Stage timestamps, logged at the end — real numbers to tune the client's
  // eta estimate against, instead of guessing from watching one run.
  const t0 = Date.now();
  const elapsed = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`;

  (async () => {
    try {
      let finalLyrics = (lyrics || "").trim();
      let title = "";
      let styleTags = genre;

      if (finalLyrics) {
        // Explicit lyrics: still let Gemini tag the style, but never rewrite
        // what the user pasted/typed.
        styleTags = `${genre}, spanish vocals, catchy, clean mix`;
      } else {
        job.status = "writing_lyrics";
        const composed = await composeLyrics({ genre, description, words, durationSec, language });
        finalLyrics = composed.lyrics;
        title = composed.title;
        styleTags = composed.styleTags;
      }
      console.log(`[music] job ${id} lyrics ready at ${elapsed()}`);

      job.status = "generating";
      // The picture plan only needs the final lyrics, so it runs concurrently
      // with the (much slower) audio render. Best-effort throughout.
      const scenePromise = composeScenePlan({ lyrics: finalLyrics, words, durationSec }).catch(() => null);
      const audio = await callMusicService({ styleTags, lyrics: finalLyrics, durationSec });
      console.log(`[music] job ${id} audio ready at ${elapsed()}`);

      // Whisper alignment from the GPU service when it worked, heuristic spread otherwise.
      const timedLines = audio.lines && audio.lines.length
        ? audio.lines
        : heuristicLineTimings(finalLyrics, durationSec);
      // Audio is already done at this point — never let a slow/rate-limited
      // Gemini scene-plan call hold the finished song hostage. Past 10s of
      // extra waiting, ship without the AI storyboard (queue words still get
      // their evenly-spread fallback scenes via resolveScenes).
      const plannedScenes = await withTimeout(scenePromise, 10_000, null);
      const scenes = resolveScenes(plannedScenes, timedLines, durationSec, words);
      console.log(`[music] job ${id} scenes ready at ${elapsed()} (${plannedScenes ? "planned" : "fallback/timeout"})`);

      job.song = {
        title: title || genre,
        lyrics: finalLyrics,
        genre,
        durationSec,
        mime: audio.mime,
        audioBase64: audio.audioBase64,
        lines: timedLines,
        scenes
      };
      job.status = "done";
      await runOutcome(onOutcome, { ok: true }, id);
    } catch (e) {
      console.error(`[music] job ${id} failed:`, e.message);
      job.status = "failed";
      job.error = e.message;
      await runOutcome(onOutcome, { ok: false, error: e.message }, id);
    }
  })();

  return job;
}

export function musicCostForDuration(durationSec) {
  if (durationSec <= 30) return config.actionCosts.musicShort;
  if (durationSec <= 60) return config.actionCosts.musicMedium;
  return config.actionCosts.musicLong;
}

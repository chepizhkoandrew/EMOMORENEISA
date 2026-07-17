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

async function composeLyrics(params) {
  const r = await geminiText({
    prompt: lyricsPrompt(params),
    model: config.music.lyricsModel,
    temperature: 0.8,
    maxOutputTokens: 2048
  });
  const cleaned = r.text.trim().replace(/```json/g, "").replace(/```/g, "").trim();
  const obj = JSON.parse(cleaned);
  if (!obj.lyrics) throw new Error("lyrics_compose_incomplete");
  return {
    title: String(obj.title || "Mi canción"),
    styleTags: String(obj.styleTags || params.genre),
    lyrics: String(obj.lyrics),
    usage: r.usage
  };
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
    return { audioBase64: json.audioBase64, mime: json.mime || "audio/mpeg" };
  } finally {
    clearTimeout(timer);
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

      job.status = "generating";
      const audio = await callMusicService({ styleTags, lyrics: finalLyrics, durationSec });

      job.song = {
        title: title || genre,
        lyrics: finalLyrics,
        genre,
        durationSec,
        mime: audio.mime,
        audioBase64: audio.audioBase64
      };
      job.status = "done";
      onOutcome?.({ ok: true });
    } catch (e) {
      console.error(`[music] job ${id} failed:`, e.message);
      job.status = "failed";
      job.error = e.message;
      onOutcome?.({ ok: false, error: e.message });
    }
  })();

  return job;
}

export function musicCostForDuration(durationSec) {
  if (durationSec <= 30) return config.actionCosts.musicShort;
  if (durationSec <= 60) return config.actionCosts.musicMedium;
  return config.actionCosts.musicLong;
}

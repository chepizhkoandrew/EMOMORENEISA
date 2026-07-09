import { config } from "./config.js";
import { JWT } from "google-auth-library";

export async function openaiChat({ systemPrompt, history, userText, imageData, maxTokens, model, temperature }) {
  const messages = [];
  if (systemPrompt) messages.push({ role: "system", content: systemPrompt });

  for (const m of history || []) {
    messages.push({ role: m.isUser ? "user" : "assistant", content: m.text || "" });
  }

  if (!imageData || imageData.length === 0) {
    messages.push({ role: "user", content: userText || "" });
  } else {
    const parts = [{ type: "text", text: userText || "" }];
    for (const b64 of imageData) {
      parts.push({ type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}` } });
    }
    messages.push({ role: "user", content: parts });
  }

  const resp = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.openaiKey}`
    },
    body: JSON.stringify({
      model: model || config.models.chat,
      messages,
      temperature: temperature ?? 0.7,
      max_tokens: maxTokens || 300
    })
  });

  const json = await resp.json();
  if (!resp.ok) {
    const err = new Error(json?.error?.message || `openai_${resp.status}`);
    err.status = resp.status;
    throw err;
  }

  return {
    text: json.choices?.[0]?.message?.content ?? "",
    usage: {
      inputTokens: json.usage?.prompt_tokens ?? 0,
      outputTokens: json.usage?.completion_tokens ?? 0
    }
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Single Gemini TTS call. Returns audio, or { retryable } so the caller can
// decide whether a backoff retry is worth it (429/5xx = transient throttling).
async function geminiTTSOnce(text, model) {
  if (!config.geminiKey) return { audio: null, retryable: false };
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${config.geminiKey}`;
  let resp;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: config.tts.voiceName } } }
        }
      })
    });
  } catch (e) {
    return { audio: null, retryable: true, status: 0 };
  }
  if (!resp.ok) {
    const retryable = resp.status === 429 || resp.status >= 500;
    let detail = "";
    try { detail = (await resp.text()).slice(0, 200); } catch (_) {}
    console.warn(`[TTS] gemini ${model} HTTP ${resp.status}${retryable ? " (retryable)" : ""}: ${detail}`);
    return { audio: null, retryable, status: resp.status };
  }
  const json = await resp.json();
  const b64 = json?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;
  // The preview TTS model intermittently returns HTTP 200 with NO audio part
  // (empty candidate / non-STOP finishReason). This is transient, not a hard
  // failure, so mark it retryable — otherwise a single flaky response silently
  // drops a Spanish segment and fails the whole drill.
  if (!b64) {
    const reason = json?.candidates?.[0]?.finishReason ?? "no_audio_part";
    console.warn(`[TTS] gemini ${model} HTTP 200 but empty audio (finishReason=${reason})`);
    return { audio: null, retryable: true, status: 200 };
  }
  return { audio: { provider: "gemini", audioBase64: b64, mime: "audio/L16;rate=24000" } };
}

// Backwards-compatible single-shot (no retry). Prefer synthesizeVoice().
export async function geminiTTS(text, model = config.models.ttsGemini) {
  const { audio } = await geminiTTSOnce(text, model);
  return audio || null;
}

// Gemini text completion via generativelanguage generateContent. Used by the
// onboarding reasoning routes (probe passes + synthesis). Returns the raw
// text body — callers are responsible for JSON.parse and validation.
export async function geminiText({ prompt, model, temperature = 0.4, maxOutputTokens = 1024, disableThinking = true }) {
  if (!config.geminiKey) {
    const err = new Error("gemini_not_configured");
    err.status = 503;
    throw err;
  }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${config.geminiKey}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature,
        maxOutputTokens,
        responseMimeType: "application/json",
        // gemini-2.5-flash reserves part of maxOutputTokens for internal
        // "thinking" tokens by default. For the short structured JSON the
        // onboarding probe uses this for, that reasoning budget was starving
        // the actual visible answer (empty/truncated text -> JSON parse
        // failure -> silent fallback to the generic question every time).
        // BUT gemini-2.5-pro (onboarding synthesis) rejects thinkingBudget:0
        // outright ("Budget 0 is invalid. This model only works in thinking
        // mode.") — so this must be opt-out per call, not blanket-disabled.
        ...(disableThinking ? { thinkingConfig: { thinkingBudget: 0 } } : {})
      }
    })
  });
  if (!resp.ok) {
    let detail = "";
    try { detail = (await resp.text()).slice(0, 300); } catch (_) {}
    const err = new Error(`gemini_text_${resp.status}: ${detail}`);
    err.status = resp.status;
    throw err;
  }
  const json = await resp.json();
  const parts = json?.candidates?.[0]?.content?.parts ?? [];
  const text = parts.map(p => p?.text ?? "").join("").trim();
  if (!text) {
    const err = new Error("gemini_text_empty");
    err.status = 502;
    throw err;
  }
  const usage = json?.usageMetadata || {};
  return {
    text,
    usage: {
      inputTokens: usage.promptTokenCount ?? 0,
      outputTokens: usage.candidatesTokenCount ?? 0
    }
  };
}

// ---------------------------------------------------------------------------
// Google Cloud Text-to-Speech (GA Chirp 3 HD). Reliable, natural Spanish.
// Auth is a service-account OAuth2 token (NOT the simple API key). The JWT
// client caches/refreshes the access token internally, so we mint it once.
// ---------------------------------------------------------------------------
let _gcpJwt = null;
function gcpJwtClient() {
  if (_gcpJwt) return _gcpJwt;
  const creds = config.cloudTts.credentials;
  if (!creds?.client_email || !creds?.private_key) return null;
  _gcpJwt = new JWT({
    email: creds.client_email,
    key: creds.private_key,
    scopes: ["https://www.googleapis.com/auth/cloud-platform"]
  });
  return _gcpJwt;
}

// REST text:synthesize with LINEAR16 returns a base64 WAV (RIFF header). Strip
// it down to the raw s16le PCM `data` chunk so the bytes match Gemini's L16
// shape and flow through the identical pcmToAac transcode + cache path.
function wavToPcm(buf) {
  if (buf.length < 12 || buf.toString("ascii", 0, 4) !== "RIFF") return buf;
  let off = 12;
  while (off + 8 <= buf.length) {
    const id = buf.toString("ascii", off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    if (id === "data") return buf.subarray(off + 8, Math.min(off + 8 + size, buf.length));
    off += 8 + size;
  }
  return buf;
}

// ---------------------------------------------------------------------------
// SSML builder — wraps plain text in context-aware SSML markup so Google Cloud
// Chirp 3 HD delivers natural, expressive Spanish for each use case.
//
// Contexts:
//   "scene"       — Street Vision AI description (multiple sentences; pauses +
//                   emphasis on object nouns detected by naive heuristic)
//   "label"       — Single annotation label tapped by the user (slower prosody
//                   so the word lands clearly for vocabulary acquisition)
//   "loro"        — Loro / memory-card phrase (emphasis on the key vocabulary
//                   word — first standalone noun/adj token in the phrase)
//   "encouragement" — Positive feedback ("¡Muy bien!", correct-answer praise)
//   "sentence"    — General chat / AI reply (pauses between sentences only)
//   "default"     — Any other call; minimal SSML wrapping, no extra markup.
// ---------------------------------------------------------------------------
function escapeXml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}

function splitSentences(text) {
  // Split on sentence-ending punctuation followed by whitespace or end-of-string.
  return text.split(/(?<=[.!?¡¿])\s+/).map(s => s.trim()).filter(Boolean);
}

export function textToSsml(text, context = "default") {
  const safe = escapeXml(text.trim());

  switch (context) {
    case "scene": {
      // Add natural breathing pauses between sentences for scene narration.
      const sentences = splitSentences(text);
      if (sentences.length <= 1) {
        return `<speak><prosody pitch="-1st">${escapeXml(sentences[0] || text)}</prosody></speak>`;
      }
      const parts = sentences.map((s, i) => {
        const pause = i === 0 ? "" : '<break time="450ms"/>';
        return `${pause}<prosody pitch="-1st">${escapeXml(s)}</prosody>`;
      });
      return `<speak>${parts.join("\n")}</speak>`;
    }

    case "label": {
      // Slow down label pronunciation so the word is clearly absorbed.
      return `<speak><prosody rate="0.82" pitch="-0.5st">${safe}</prosody></speak>`;
    }

    case "loro": {
      // Loro cards: the whole phrase, but first content word gets emphasis
      // so the learner's ear locks onto the vocabulary target.
      const words = text.trim().split(/\s+/);
      if (words.length <= 1) {
        return `<speak><emphasis level="strong">${safe}</emphasis></speak>`;
      }
      // Skip leading function words (articles/prepositions) to emphasise the noun/verb.
      const skip = new Set(["el","la","los","las","un","una","unos","unas","de","del","a","en","y","o","que","es","son"]);
      let emphIdx = words.findIndex(w => !skip.has(w.toLowerCase().replace(/[^a-záéíóúñü]/gi,"")));
      if (emphIdx < 0) emphIdx = 0;
      const built = words.map((w, i) =>
        i === emphIdx
          ? `<emphasis level="moderate">${escapeXml(w)}</emphasis>`
          : escapeXml(w)
      ).join(" ");
      return `<speak>${built}</speak>`;
    }

    case "encouragement": {
      // Warm, slightly up-beat tone for praise ("¡Muy bien!", correct answers).
      return `<speak><prosody pitch="+2st" rate="1.05">${safe}</prosody></speak>`;
    }

    case "sentence": {
      // General chat messages: just add sentence-boundary pauses.
      const sentences = splitSentences(text);
      if (sentences.length <= 1) return `<speak>${safe}</speak>`;
      const parts = sentences.map((s, i) =>
        i === 0 ? escapeXml(s) : `<break time="350ms"/>${escapeXml(s)}`
      );
      return `<speak>${parts.join("\n")}</speak>`;
    }

    default:
      return `<speak>${safe}</speak>`;
  }
}

export async function cloudTTS(text, context = "default", voiceOverride = null) {
  const ssml = textToSsml(text, context);
  const client = gcpJwtClient();
  if (!client) return null;
  const languageCode = voiceOverride?.languageCode || config.cloudTts.languageCode;
  const voiceName = voiceOverride?.voiceName || config.cloudTts.voiceName;
  let token;
  try {
    token = (await client.getAccessToken())?.token;
  } catch (e) {
    console.warn(`[TTS] cloud token error: ${e.message}`);
    return null;
  }
  if (!token) return null;

  let resp;
  try {
    resp = await fetch("https://texttospeech.googleapis.com/v1/text:synthesize", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        input: { ssml },
        voice: { languageCode, name: voiceName },
        audioConfig: { audioEncoding: "LINEAR16", sampleRateHertz: 24000, speakingRate: config.cloudTts.speakingRate }
      })
    });
  } catch (e) {
    console.warn(`[TTS] cloud fetch error: ${e.message}`);
    return null;
  }
  if (!resp.ok) {
    let detail = "";
    try { detail = (await resp.text()).slice(0, 200); } catch (_) {}
    console.warn(`[TTS] cloud HTTP ${resp.status}: ${detail}`);
    return null;
  }
  const json = await resp.json();
  const b64 = json?.audioContent;
  if (!b64) {
    console.warn("[TTS] cloud HTTP 200 but empty audioContent");
    return null;
  }
  const pcm = wavToPcm(Buffer.from(b64, "base64"));
  return { provider: "googlecloud", audioBase64: pcm.toString("base64"), mime: "audio/L16;rate=24000" };
}

// Voice synthesis. PRIMARY is Google Cloud TTS (GA, reliable Spanish) when
// credentials are configured; otherwise it falls through to the Gemini preview
// retry/backoff loop and finally the multilingual OpenAI voice, so audio is
// never silent. A Spanish segment only fails honestly (returns null) when every
// engine is unavailable, letting the caller refund instead of shipping silence.
export async function synthesizeVoice(text, { allowOpenAIFallback = false, context = "default", voiceOverride = null } = {}) {
  // Primary: Google Cloud TTS (GA Chirp 3 HD) — no preview empty-audio drops.
  if (config.cloudTts.enabled) {
    const cloud = await cloudTTS(text, context, voiceOverride);
    if (cloud) return cloud;
    console.warn("[TTS] cloud TTS unavailable — falling through to Gemini/OpenAI");
  }

  const models = [config.models.ttsGemini];
  if (config.models.ttsGeminiFallback && config.models.ttsGeminiFallback !== config.models.ttsGemini) {
    models.push(config.models.ttsGeminiFallback);
  }
  const attemptsPerModel = Math.max(1, 1 + config.tts.retries);

  for (const model of models) {
    for (let attempt = 0; attempt < attemptsPerModel; attempt++) {
      const { audio, retryable } = await geminiTTSOnce(text, model);
      if (audio) return audio;
      if (!retryable) break; // hard failure on this model; move to the next model
      if (attempt < attemptsPerModel - 1) {
        // Exponential backoff with full jitter so concurrent segments that all
        // hit the per-minute 429 don't retry in lockstep and re-collide.
        const ceil = config.tts.retryBaseMs * Math.pow(2, attempt);
        await sleep(Math.floor(ceil / 2 + Math.random() * (ceil / 2)));
      }
    }
  }

  // Live fallback: when Gemini is rate-limited / degraded, synthesize with the
  // multilingual OpenAI voice model (gpt-4o-mini-tts) so audio is never silent.
  // Enabled by default; set TTS_ALLOW_OPENAI_FALLBACK=false to force Gemini-only.
  if (allowOpenAIFallback && config.tts.allowOpenAIFallback) {
    console.warn("[TTS] gemini failed — falling back to OpenAI voice");
    return await openaiTTS(text);
  }
  return null;
}

// Returns raw s16le PCM @ 24kHz mono (same shape as Gemini's L16) so it flows
// through the identical pcmToAac transcode + cache path.
export async function openaiTTS(text) {
  if (!config.openaiKey) return null;
  const resp = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.openaiKey}`
    },
    body: JSON.stringify({
      model: config.models.ttsOpenAI,
      voice: config.tts.openaiVoice,
      input: text,
      response_format: "pcm"
    })
  });
  if (!resp.ok) {
    let detail = "";
    try { detail = (await resp.text()).slice(0, 200); } catch (_) {}
    console.warn(`[TTS] openai fallback HTTP ${resp.status}: ${detail}`);
    return null;
  }
  const buf = Buffer.from(await resp.arrayBuffer());
  return { provider: "openai", audioBase64: buf.toString("base64"), mime: "audio/L16;rate=24000" };
}

// ---------------------------------------------------------------------------
// Vertex AI image generation (Gemini 2.5 Flash Image / "nano banana").
// Runs on Google Cloud with the same service-account OAuth2 token as Cloud TTS
// (Vertex AI must be enabled on the account), so the memorization-illustration
// generator never touches the rate-limited generativelanguage preview endpoint.
// ---------------------------------------------------------------------------

// Fixed style anchor: every illustration shares this so the cache stays
// consistent AND the learner builds associations against ONE recognizable art
// style. Bump STYLE_ANCHOR_VERSION (in imagecache.js) if this text changes.
const ILLUSTRATION_STYLE_ANCHOR =
  "Consistent art style for every image: a warm, flat vector children's-book " +
  "illustration with bold clean outlines, soft cel shading, and a cheerful " +
  "sunny pastel palette. One clear central subject on a simple, uncluttered " +
  "background, centered square composition, cute and highly expressive. " +
  "Absolutely no text, letters, numbers, speech bubbles, or words anywhere in " +
  "the image.";

// Builds the prompt for a phrase. Only the SUBJECT block varies; the style
// anchor is constant so every picture looks like it belongs to the same set.
// The goal is a mnemonic: one concrete, slightly exaggerated, emotionally
// memorable scene that instantly captures the meaning so the learner forms a
// strong association. A friendly recurring cartoon seagull mascot may act the
// phrase out when it involves a person/greeting/action; otherwise the concept
// is shown directly (an animal, plant, object, or simple visual metaphor). The
// model decides from the sense, so the output stays deterministic per phrase.
export function buildIllustrationPrompt(spanish, english) {
  const english_ = (english || "").trim();
  const spanish_ = (spanish || "").trim();
  const meaning = english_ || spanish_;
  const phraseLine = english_ && spanish_
    ? `the phrase "${spanish_}" (which means "${english_}")`
    : `the phrase "${meaning}"`;
  return (
    `${ILLUSTRATION_STYLE_ANCHOR}\n\n` +
    `Subject: turn ${phraseLine} into ONE concrete, vivid, slightly ` +
    `exaggerated and charming scene that a language learner will instantly ` +
    `recognize and remember. Use a single obvious focal subject — a character ` +
    `clearly performing the action, or one memorable object. For abstract ` +
    `meanings, use a simple, playful visual metaphor. Make it emotionally ` +
    `expressive and cute so it forms a strong mental hook tied to the meaning.`
  );
}

// Calls Vertex :generateContent asking for an IMAGE modality. Returns
// { base64, mime } on success or null on any failure (429/5xx/empty) so the
// caller can degrade to the seagull pose without ever throwing.
export async function generateIllustration(prompt) {
  const cfg = config.vertexImage;
  if (!cfg.enabled || !cfg.projectId) return null;
  const client = gcpJwtClient();
  if (!client) return null;

  let token;
  try {
    token = (await client.getAccessToken())?.token;
  } catch (e) {
    console.warn(`[IMG] vertex token error: ${e.message}`);
    return null;
  }
  if (!token) return null;

  const host = cfg.location === "global"
    ? "aiplatform.googleapis.com"
    : `${cfg.location}-aiplatform.googleapis.com`;
  const url =
    `https://${host}/v1/projects/${cfg.projectId}/locations/${cfg.location}` +
    `/publishers/google/models/${cfg.model}:generateContent`;

  // Hard timeout so a slow/hung Vertex call can never hold the loro stream open
  // past the audio — on abort we simply degrade to the seagull pose.
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 25000);
  let resp;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { responseModalities: ["IMAGE"] }
      }),
      signal: ac.signal
    });
  } catch (e) {
    console.warn(`[IMG] vertex fetch error: ${e.message}`);
    return null;
  } finally {
    clearTimeout(timer);
  }
  if (!resp.ok) {
    let detail = "";
    try { detail = (await resp.text()).slice(0, 200); } catch (_) {}
    console.warn(`[IMG] vertex HTTP ${resp.status}: ${detail}`);
    return null;
  }

  let json;
  try {
    json = await resp.json();
  } catch (e) {
    console.warn(`[IMG] vertex bad JSON: ${e.message}`);
    return null;
  }
  const parts = json?.candidates?.[0]?.content?.parts || [];
  for (const p of parts) {
    const inline = p?.inlineData || p?.inline_data;
    if (inline?.data) {
      return { base64: inline.data, mime: inline.mimeType || inline.mime_type || "image/png" };
    }
  }
  console.warn("[IMG] vertex HTTP 200 but no inline image data");
  return null;
}

// Speech-to-text via OpenAI. gpt-4o-transcribe is the most accurate at catching
// Spanish word endings. `prompt` biases spelling/accents; `language` is an ISO
// hint ("es"/"en") — omitted when unknown so the model auto-detects.
export async function openaiTranscribe(audioBuffer, { filename = "audio.m4a", mimeType = "audio/mp4", language, prompt } = {}) {
  if (!config.openaiKey) return { text: "", error: "not_configured" };
  const form = new FormData();
  const blob = new Blob([audioBuffer], { type: mimeType });
  form.append("file", blob, filename);
  form.append("model", config.models.transcribe);
  form.append("response_format", "text");
  if (language) form.append("language", language);
  if (prompt) form.append("prompt", prompt);

  const resp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${config.openaiKey}` },
    body: form
  });
  if (!resp.ok) {
    let detail = "";
    try { detail = (await resp.text()).slice(0, 200); } catch (_) {}
    console.warn(`[STT] openai transcribe HTTP ${resp.status}: ${detail}`);
    return { text: "", error: `openai_${resp.status}` };
  }
  const text = (await resp.text()).trim();
  return { text };
}

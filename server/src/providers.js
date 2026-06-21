import { config } from "./config.js";

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
    return { audio: null, retryable, status: resp.status };
  }
  const json = await resp.json();
  const b64 = json?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;
  // The preview TTS model intermittently returns HTTP 200 with NO audio part
  // (empty candidate / non-STOP finishReason). This is transient, not a hard
  // failure, so mark it retryable — otherwise a single flaky response silently
  // drops a Spanish segment and fails the whole drill.
  return b64
    ? { audio: { provider: "gemini", audioBase64: b64, mime: "audio/L16;rate=24000" } }
    : { audio: null, retryable: true, status: 200 };
}

// Backwards-compatible single-shot (no retry). Prefer synthesizeVoice().
export async function geminiTTS(text, model = config.models.ttsGemini) {
  const { audio } = await geminiTTSOnce(text, model);
  return audio || null;
}

// Gemini-ONLY voice synthesis with retry + backoff across the primary and a
// (also-Gemini) fallback model. Never silently switches to a different-language
// engine: a Spanish segment that cannot be voiced by Gemini fails honestly so
// the caller can refund instead of shipping English-accented Spanish audio.
// OpenAI is only ever touched when a deploy explicitly opts in via config.
export async function synthesizeVoice(text, { allowOpenAIFallback = false } = {}) {
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

  // Opt-in only. OpenAI's voice mispronounces Spanish, so this stays off unless
  // a deploy sets TTS_ALLOW_OPENAI_FALLBACK=true (e.g. for English-only text).
  if (allowOpenAIFallback && config.tts.allowOpenAIFallback) {
    return await openaiTTS(text);
  }
  return null;
}

export async function openaiTTS(text) {
  if (!config.openaiKey) return null;
  const resp = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.openaiKey}`
    },
    body: JSON.stringify({ model: config.models.ttsOpenAI, voice: "onyx", input: text, response_format: "wav" })
  });
  if (!resp.ok) return null;
  const buf = Buffer.from(await resp.arrayBuffer());
  return { provider: "openai", audioBase64: buf.toString("base64"), mime: "audio/wav" };
}

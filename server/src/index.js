import express from "express";
import { config, featureFlags } from "./config.js";
import { requireUser } from "./auth.js";
import { openaiChat, openaiTranscribe } from "./providers.js";
import { getVoice } from "./voicecache.js";
import { chatCostUsd, ttsCostUsd, analystCostUsd } from "./pricing.js";
import { getWallet, debit, credit, grantTrialIfNeeded, recordTopup } from "./wallet.js";
import { supabase } from "./supabase.js";
import { record } from "./meter.js";
import { verifyStoreKitJWS } from "./appstore.js";

const app = express();
app.use(express.json({ limit: "12mb" }));

app.get("/healthz", (req, res) => {
  res.json({ ok: true, service: "professor-madrid-api", version: "0.1.0", features: featureFlags() });
});

// Builds the Loro drill script (one LLM call -> spanish/english/sentence1/sentence2).
// Throws on a malformed/incomplete response so callers can refund + fail honestly.
async function buildLoroScript(prompt) {
  const r = await openaiChat({ userText: prompt, model: config.models.analyst, maxTokens: 200, temperature: 0.3 });
  const cleaned = (r.text || "").trim().replace(/```json/g, "").replace(/```/g, "").trim();
  const obj = JSON.parse(cleaned);
  if (!obj.spanish || !obj.english || !obj.sentence1 || !obj.sentence2) throw new Error("incomplete_script");
  return obj;
}

// The 7 playback positions reference only the DISTINCT strings below (the Spanish
// word repeats 4x). Shared by /v1/loro and /v1/loro/stream.
function loroSegmentTexts(script) {
  return [
    script.spanish, script.english, script.spanish, script.spanish,
    script.spanish, script.sentence1, script.sentence2
  ];
}

function walletPayload(userId, wallet) {
  return {
    userId,
    balanceTreats: wallet ? Number(wallet.balance_treats) : 0,
    hasPaid: wallet ? Boolean(wallet.has_paid) : false,
    trialGranted: wallet ? Boolean(wallet.trial_granted) : false,
    enforced: config.enforceWallet
  };
}

// Call right after sign-in: ensures wallet, grants the one-time trial, returns state.
app.post("/v1/bootstrap", requireUser, async (req, res) => {
  await grantTrialIfNeeded(req.user.id);
  const wallet = await getWallet(req.user.id);
  res.json(walletPayload(req.user.id, wallet));
});

app.get("/v1/wallet", requireUser, async (req, res) => {
  const wallet = await getWallet(req.user.id);
  res.json(walletPayload(req.user.id, wallet));
});

// Catalog of treat packs so the client can render the paywall from one source.
app.get("/v1/packs", requireUser, (req, res) => {
  res.json({ packs: config.packs, trialGrantTreats: config.trialGrantTreats });
});

app.post("/v1/chat", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });

  const { systemPrompt, history, userText, imageData, maxTokens } = req.body || {};
  const hasImages = Array.isArray(imageData) && imageData.length > 0;
  const model = hasImages ? config.models.vision : config.models.chat;

  // Flat per-action treat cost (predictable for users); refunded if upstream fails.
  const cost = hasImages ? config.actionCosts.streetView : config.actionCosts.chat;
  const kind = hasImages ? "vision" : "chat";
  const reason = hasImages ? "street_view_message" : "chat_message";

  const pre = await debit(req.user.id, cost, reason, { model });
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  try {
    const result = await openaiChat({ systemPrompt, history, userText, imageData, maxTokens, model });
    const rawCost = chatCostUsd(result.usage.inputTokens, result.usage.outputTokens);
    await record({
      userId: req.user.id,
      kind,
      provider: "openai",
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
      rawCostUsd: rawCost,
      treatsCharged: cost
    });
    res.json({ text: result.text, usage: result.usage, treatsCharged: cost });
  } catch (e) {
    if (pre.enforced) await credit(req.user.id, cost, "refund", `${reason}_failed`, {});
    res.status(e.status || 502).json({ error: "upstream_error", detail: e.message });
  }
});

app.post("/v1/tts", requireUser, async (req, res) => {
  const { text } = req.body || {};
  if (!text || typeof text !== "string") return res.status(400).json({ error: "missing_text" });
  const format = req.body?.format === "aac" ? "aac" : "pcm";
  const validContexts = new Set(["scene","label","loro","encouragement","sentence","default"]);
  const context = (typeof req.body?.context === "string" && validContexts.has(req.body.context))
    ? req.body.context : "default";

  const cost = config.actionCosts.voice;
  const pre = await debit(req.user.id, cost, "voice_message", {});
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  const audio = await getVoice(text, { format, context });
  if (!audio) {
    if (pre.enforced) await credit(req.user.id, cost, "refund", "voice_message_failed", {});
    return res.status(502).json({ error: "tts_failed" });
  }

  // A cache hit costs us nothing (no Gemini call); record 0 raw cost for it.
  const provider = audio.cached ? "cache" : "gemini";
  const estSeconds = Math.max(1, Math.round(text.length / 14));
  const rawCost = audio.cached ? 0 : ttsCostUsd("gemini", estSeconds);
  await record({
    userId: req.user.id,
    kind: "tts",
    provider,
    seconds: estSeconds,
    rawCostUsd: rawCost,
    treatsCharged: cost
  });

  res.json({ provider: audio.provider, mime: audio.mime, audioBase64: audio.audioBase64, treatsCharged: cost });
});

// Speech-to-text. Routed server-side through OpenAI gpt-4o-transcribe (most
// accurate at Spanish word endings) so the mic no longer depends on the flaky
// preview Gemini path. Not separately debited — the turn it belongs to (chat /
// voice / verb-check) is what carries the cost.
app.post("/v1/transcribe", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "stt_not_configured" });
  const { audioBase64, mime, language, prompt } = req.body || {};
  if (!audioBase64 || typeof audioBase64 !== "string") {
    return res.status(400).json({ error: "missing_audio" });
  }

  let buf;
  try {
    buf = Buffer.from(audioBase64, "base64");
  } catch (_) {
    return res.status(400).json({ error: "bad_audio" });
  }
  if (!buf.length) return res.status(400).json({ error: "empty_audio" });

  const mimeType = typeof mime === "string" && mime ? mime : "audio/mp4";
  const ext = mimeType.includes("wav") ? "wav" : mimeType.includes("mpeg") ? "mp3" : "m4a";

  try {
    const { text, error } = await openaiTranscribe(buf, {
      filename: `audio.${ext}`,
      mimeType,
      language: typeof language === "string" && language ? language : undefined,
      prompt: typeof prompt === "string" && prompt ? prompt : undefined
    });
    if (error) return res.status(502).json({ error: "stt_failed", detail: error });
    res.json({ text });
  } catch (e) {
    res.status(502).json({ error: "stt_failed", detail: e.message });
  }
});

// Utility completions (transcript enhancement, session summary, background analyst).
// NOT debited: these are short, capped, and run on the user's behalf in the background.
app.post("/v1/utility", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });
  const { prompt, kind, maxTokens, temperature } = req.body || {};
  if (!prompt || typeof prompt !== "string") return res.status(400).json({ error: "missing_prompt" });

  const model = kind === "analyst" ? config.models.analyst : config.models.chat;
  try {
    const result = await openaiChat({
      userText: prompt,
      model,
      maxTokens: maxTokens || 256,
      temperature: temperature ?? 0
    });
    const rawCost = kind === "analyst"
      ? analystCostUsd(result.usage.inputTokens, result.usage.outputTokens)
      : chatCostUsd(result.usage.inputTokens, result.usage.outputTokens);
    await record({
      userId: req.user.id,
      kind: "utility",
      provider: "openai",
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
      rawCostUsd: rawCost,
      treatsCharged: 0
    });
    res.json({ text: result.text });
  } catch (e) {
    res.status(e.status || 502).json({ error: "upstream_error", detail: e.message });
  }
});

// Loro/Parrot drill: build the script (one LLM call) + all TTS segments server-side,
// debited as a SINGLE flat action so users are not charged per voice segment.
app.post("/v1/loro", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });
  const { prompt } = req.body || {};
  if (!prompt || typeof prompt !== "string") return res.status(400).json({ error: "missing_prompt" });

  const cost = config.actionCosts.loro;
  const pre = await debit(req.user.id, cost, "loro_drill", {});
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  const refund = async (reason) => {
    if (pre.enforced) await credit(req.user.id, cost, "refund", reason, {});
  };

  let script;
  try {
    script = await buildLoroScript(prompt);
  } catch (e) {
    await refund("loro_script_failed");
    return res.status(502).json({ error: "loro_script_failed", detail: e.message });
  }

  const segmentTexts = loroSegmentTexts(script);
  const format = req.body?.format === "aac" ? "aac" : "pcm";

  // The 7 positions reference only a handful of UNIQUE strings (the Spanish word
  // alone repeats 4x). Gemini's preview TTS model is rate-limited per minute, so
  // we synthesize each DISTINCT text exactly once and fan the buffers back out to
  // the 7 positions. This roughly halves the API calls (7 -> ~4), which is the
  // difference between fitting under the quota and getting throttled (429 ->
  // English-voiced Spanish, the bug we are fixing). The shared AAC cache cuts it
  // further: a previously-seen text is served from storage with no Gemini call.
  const uniqueTexts = [...new Set(segmentTexts)];
  const audioByText = new Map();
  const concurrency = Math.max(1, config.tts.loroConcurrency);
  let nextIdx = 0;
  const worker = async () => {
    while (true) {
      const i = nextIdx++;
      if (i >= uniqueTexts.length) return;
      const t = uniqueTexts[i];
      audioByText.set(t, await getVoice(t, { format }));
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, uniqueTexts.length) }, worker));

  const results = segmentTexts.map((t) => audioByText.get(t));
  if (results.some((a) => !a)) {
    await refund("loro_tts_failed");
    return res.status(502).json({ error: "loro_tts_failed" });
  }

  const provider = "gemini";
  const segments = results.map((a) => ({ audioBase64: a.audioBase64, mime: a.mime }));
  // Only bill raw cost for UNIQUE texts that actually hit Gemini (cache hits = $0).
  const billedSeconds = uniqueTexts.reduce((s, t) => {
    return audioByText.get(t)?.cached ? s : s + Math.max(1, Math.round(t.length / 14));
  }, 0);
  const totalSeconds = segmentTexts.reduce((s, t) => s + Math.max(1, Math.round(t.length / 14)), 0);

  await record({
    userId: req.user.id,
    kind: "loro",
    provider,
    seconds: totalSeconds,
    rawCostUsd: ttsCostUsd(provider, billedSeconds),
    treatsCharged: cost
  });

  res.json({
    spanish: script.spanish,
    english: script.english,
    sentence1: script.sentence1,
    sentence2: script.sentence2,
    segments,
    treatsCharged: cost
  });
});

// Streaming variant of /v1/loro for newer app builds: emits NDJSON so the client
// can start playing segment 0 (the Spanish word) while later segments are still
// being synthesized. Same single flat "loro" debit + refund-on-failure semantics
// as /v1/loro; the older JSON endpoint is kept intact for already-shipped builds.
app.post("/v1/loro/stream", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });
  const { prompt } = req.body || {};
  if (!prompt || typeof prompt !== "string") return res.status(400).json({ error: "missing_prompt" });

  const cost = config.actionCosts.loro;
  const pre = await debit(req.user.id, cost, "loro_drill", {});
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  const refund = async (reason) => {
    if (pre.enforced) await credit(req.user.id, cost, "refund", reason, {});
  };

  // Build the script BEFORE switching to a streaming response so we can still
  // return a clean HTTP error status (and refund) if the LLM call fails.
  let script;
  try {
    script = await buildLoroScript(prompt);
  } catch (e) {
    await refund("loro_script_failed");
    return res.status(502).json({ error: "loro_script_failed", detail: e.message });
  }

  const segmentTexts = loroSegmentTexts(script);
  const format = req.body?.format === "aac" ? "aac" : "pcm";
  const provider = "gemini";

  res.status(200);
  res.setHeader("Content-Type", "application/x-ndjson");
  res.setHeader("Cache-Control", "no-cache");
  const write = (obj) => res.write(JSON.stringify(obj) + "\n");

  write({
    type: "meta",
    spanish: script.spanish,
    english: script.english,
    sentence1: script.sentence1,
    sentence2: script.sentence2,
    totalSegments: segmentTexts.length,
    treatsCharged: cost
  });

  // Synthesize each DISTINCT text once (the Spanish word repeats 4x). As each
  // unique buffer lands, emit it to EVERY playback position that references it,
  // emitting the Spanish word (index 0) first so playback can begin immediately.
  const uniqueTexts = [...new Set(segmentTexts)];
  const positionsByText = new Map();
  segmentTexts.forEach((t, i) => {
    if (!positionsByText.has(t)) positionsByText.set(t, []);
    positionsByText.get(t).push(i);
  });

  const concurrency = Math.max(1, config.tts.loroConcurrency);
  let nextIdx = 0;
  let failed = false;
  let billedSeconds = 0; // raw COGS only for texts that actually hit Gemini.
  const worker = async () => {
    while (!failed) {
      const i = nextIdx++;
      if (i >= uniqueTexts.length) return;
      const t = uniqueTexts[i];
      const audio = await getVoice(t, { format });
      if (!audio) { failed = true; return; }
      if (!audio.cached) billedSeconds += Math.max(1, Math.round(t.length / 14));
      for (const pos of positionsByText.get(t)) {
        write({ type: "segment", index: pos, mime: audio.mime, audioBase64: audio.audioBase64 });
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, uniqueTexts.length) }, worker));

  if (failed) {
    await refund("loro_tts_failed");
    write({ type: "error", error: "loro_tts_failed" });
    return res.end();
  }

  const totalSeconds = segmentTexts.reduce((s, t) => s + Math.max(1, Math.round(t.length / 14)), 0);
  await record({
    userId: req.user.id,
    kind: "loro",
    provider,
    seconds: totalSeconds,
    rawCostUsd: ttsCostUsd(provider, billedSeconds),
    treatsCharged: cost
  });

  write({ type: "done", totalSeconds });
  res.end();
});

// Street Vision annotation: given an image and the Spanish object list already
// produced by /v1/chat, returns normalized (x,y) centers for each object so the
// app can render interactive leader-line annotations over the photo.
app.post("/v1/annotate", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });

  const { imageData, objectList } = req.body || {};
  if (!Array.isArray(imageData) || imageData.length === 0) {
    return res.status(400).json({ error: "missing_image" });
  }

  const cost = config.actionCosts.annotate;
  const pre = await debit(req.user.id, cost, "annotate_image", { model: config.models.vision });
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  const prompt = `Look at this image carefully. The following objects were identified in it from a Spanish description: "${objectList || "objects in the scene"}"

For each distinct visible object or element in the image, return a JSON array where each item has:
- "label": the concise Spanish label (noun + adjective when appropriate, 1-3 words, e.g. "perro marrón", "mesa roja", "gorra azul")
- "translation": the English translation of the label (1-3 words, e.g. "brown dog", "red table", "blue cap")
- "x": the horizontal center of the object as a decimal from 0.0 (left edge) to 1.0 (right edge)
- "y": the vertical center of the object as a decimal from 0.0 (top edge) to 1.0 (bottom edge)

IMPORTANT RULES:
- The (x, y) coordinates must point to the exact visual center of ONE specific instance of the object in the image. Do not average across multiple instances.
- If there are multiple identical objects (e.g. three candles, two chairs), pick the single most clearly visible one and point precisely to its center. Do not place the dot between them.
- Each annotation must correspond to a single, distinct object whose center you can pinpoint precisely.

Return between 3 and 8 annotations for the most visually prominent objects. The labels must match the objects mentioned in the Spanish description. Return ONLY a valid JSON array with no other text, no markdown, no explanation.
Example: [{"label":"perro marrón","translation":"brown dog","x":0.3,"y":0.65},{"label":"mesa de madera","translation":"wooden table","x":0.7,"y":0.4}]`;

  try {
    const result = await openaiChat({
      userText: prompt,
      imageData,
      model: config.models.vision,
      maxTokens: 500,
      temperature: 0.1
    });

    const cleaned = (result.text || "").trim().replace(/```json/g, "").replace(/```/g, "").trim();
    let annotations;
    try {
      annotations = JSON.parse(cleaned);
      if (!Array.isArray(annotations)) throw new Error("not_array");
    } catch (_) {
      if (pre.enforced) await credit(req.user.id, cost, "refund", "annotate_parse_failed", {});
      return res.status(502).json({ error: "annotate_parse_failed", detail: "Model did not return valid JSON" });
    }

    annotations = annotations
      .filter(a => typeof a.label === "string" && typeof a.x === "number" && typeof a.y === "number")
      .map(a => ({ label: a.label.trim(), translation: typeof a.translation === "string" ? a.translation.trim() : "", x: Math.min(1, Math.max(0, a.x)), y: Math.min(1, Math.max(0, a.y)) }));

    const rawCost = chatCostUsd(result.usage.inputTokens, result.usage.outputTokens);
    await record({
      userId: req.user.id,
      kind: "annotate",
      provider: "openai",
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
      rawCostUsd: rawCost,
      treatsCharged: cost
    });

    res.json({ annotations, treatsCharged: cost });
  } catch (e) {
    if (pre.enforced) await credit(req.user.id, cost, "refund", "annotate_failed", {});
    res.status(e.status || 502).json({ error: "annotate_failed", detail: e.message });
  }
});

// Validate a spoken Spanish verb conjugation. Charges per word so users are
// only billed for what they actually attempt, not for the whole game session.
app.post("/v1/verb-check", requireUser, async (req, res) => {
  const { transcript, expected, infinitive, pronoun } = req.body || {};
  if (!transcript || !expected) {
    return res.status(400).json({ error: "missing_fields" });
  }

  const normalizedTranscript = transcript.trim().toLowerCase().replace(/[.,!?¿¡;:"'()\[\]]+$/, "").replace(/^[.,!?¿¡;:"'()\[\]]+/, "").trim();

  const cost = config.actionCosts.verbCheck;
  const pre = await debit(req.user.id, cost, "verb_check", {});
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  const prompt = `Spanish verb conjugation check.
Verb: "${infinitive || ""}", Pronoun: "${pronoun || ""}"
Expected conjugation: "${expected}"
User said (speech-to-text): "${normalizedTranscript}"

RULES — mark CORRECT if:
- The user said the exact conjugation (with or without the subject pronoun).
- Capitalization differences (e.g. "Partes" vs "partes") are CORRECT — ignore case entirely.
- Accent marks differ only (miró vs miro are the same word for this check).
- A single-character STT artifact (b/v swap, missing or extra 's') is the only difference.
- Trailing punctuation from speech recognition (period, comma) should be ignored.

Mark WRONG if:
- The user said a different conjugation (wrong ending, wrong tense, or a completely different word).
- The ending is wrong — endings are the most important part. "hablo" vs "habla" is WRONG.

Reply with exactly one word: CORRECT or WRONG`;

  try {
    const geminiKey = config.geminiKey;
    if (!geminiKey) {
      if (pre.enforced) await credit(req.user.id, cost, "refund", "verb_check_no_key", {});
      return res.status(503).json({ error: "verb_check_not_configured" });
    }

    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`;
    const body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0, maxOutputTokens: 8 }
    };

    const response = await fetch(geminiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(8000)
    });

    if (!response.ok) {
      if (pre.enforced) await credit(req.user.id, cost, "refund", "verb_check_api_error", {});
      return res.status(502).json({ error: "verb_check_api_error" });
    }

    const json = await response.json();
    const text = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    const correct = text.trim().toUpperCase().startsWith("CORRECT");

    res.json({ correct, treatsCharged: cost });
  } catch (e) {
    if (pre.enforced) await credit(req.user.id, cost, "refund", "verb_check_failed", {});
    res.status(502).json({ error: "verb_check_failed", detail: e.message });
  }
});

// Verify a StoreKit 2 signed transaction (JWS) and credit the matching pack.
app.post("/v1/topup", requireUser, async (req, res) => {
  const { signedTransaction } = req.body || {};
  if (!signedTransaction || typeof signedTransaction !== "string") {
    return res.status(400).json({ error: "missing_signed_transaction" });
  }

  let payload;
  try {
    payload = verifyStoreKitJWS(signedTransaction);
  } catch (e) {
    return res.status(400).json({ error: "invalid_transaction", detail: e.message });
  }

  if (payload.bundleId !== config.appleBundleId) {
    return res.status(400).json({ error: "bundle_mismatch" });
  }

  const pack = config.packs[payload.productId];
  if (!pack) return res.status(400).json({ error: "unknown_product", productId: payload.productId });

  const transactionId = String(payload.transactionId || "");
  if (!transactionId) return res.status(400).json({ error: "missing_transaction_id" });

  const result = await recordTopup({
    userId: req.user.id,
    productId: payload.productId,
    usd: pack.usd,
    baseTreats: pack.baseTreats,
    bonusPct: pack.bonusPct,
    totalTreats: pack.totalTreats,
    transactionId
  });

  if (!result.ok) return res.status(502).json({ error: "credit_failed", detail: result.error });

  const wallet = await getWallet(req.user.id);
  res.json({ ...walletPayload(req.user.id, wallet), duplicate: Boolean(result.duplicate), creditedTreats: result.duplicate ? 0 : pack.totalTreats });
});

// Redeem a coupon code. The RPC validates the code, prevents double-redemption,
// increments the use counter, and credits the wallet atomically.
app.post("/v1/coupon/redeem", requireUser, async (req, res) => {
  const { code } = req.body || {};
  if (!code || typeof code !== "string" || !code.trim()) {
    return res.status(400).json({ error: "missing_code" });
  }

  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "wallet_not_configured" });

  const { data, error } = await sb.rpc("redeem_coupon", {
    p_user_id: req.user.id,
    p_code: code.trim().toUpperCase()
  });

  if (error) return res.status(502).json({ error: "redeem_failed", detail: error.message });

  if (!data.ok) {
    const statusMap = {
      not_found: 404,
      inactive: 404,
      expired: 410,
      max_uses: 410,
      already_redeemed: 409
    };
    return res.status(statusMap[data.error] || 400).json({ error: data.error });
  }

  const wallet = await getWallet(req.user.id);
  res.json({
    ...walletPayload(req.user.id, wallet),
    creditedTreats: Number(data.treats_credited)
  });
});

app.use((req, res) => res.status(404).json({ error: "not_found" }));

app.listen(config.port, () => {
  console.log(`professor-madrid-api listening on :${config.port}`);
});

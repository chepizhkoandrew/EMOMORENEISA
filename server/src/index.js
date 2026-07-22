import express from "express";
import { config, featureFlags } from "./config.js";
import { requireUser } from "./auth.js";
import { openaiChat, openaiTranscribe, geminiText } from "./providers.js";
import { getVoice, activeVoiceTag } from "./voicecache.js";
import { probePass1Prompt, probePass2Prompt, synthesisPrompt, ONBOARDING_QUIZ_VERSION } from "./onboardingPrompts.js";
import { getIllustration, getIllustrationFromPrompt } from "./imagecache.js";
import { compositeMascot } from "./composite.js";
import { chatCostUsd, ttsCostUsd, analystCostUsd, imageCostUsd, geminiLiteCostUsd } from "./pricing.js";
import { getWallet, debit, credit, grantTrialIfNeeded, recordTopup } from "./wallet.js";
import { supabase } from "./supabase.js";
import { record } from "./meter.js";
import { verifyStoreKitJWS } from "./appstore.js";
import { startMusicJob, getMusicJob, musicConfigured, musicCostForDuration } from "./music.js";
import {
  claimPendingSocial, inviteByEmail, createInviteLink, claimInvite,
  publicInviteInfo, listFriends, respondToInvite, unfriend, blockUser, unblockUser
} from "./social.js";
import { shareSong, listSharedSongs, downloadSharedSong } from "./shares.js";
import {
  requireAdmin, createAnnouncement, announceAnnouncement,
  retireAnnouncement, bulkAckAnnouncement, fanOutPackPurchase
} from "./notifications.js";

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
// Also binds any social references addressed to this email before the account
// existed (song shares, targeted invite links) — idempotent, safe every sign-in.
app.post("/v1/bootstrap", requireUser, async (req, res) => {
  await grantTrialIfNeeded(req.user.id);
  await claimPendingSocial(req.user.id, req.user.email);
  const wallet = await getWallet(req.user.id);
  res.json(walletPayload(req.user.id, wallet));
});

// ---------------------------------------------------------------------------
// Social: friend invites, friendships, blocks, song sharing, notifications.
// All graph mutations run here (service_role); the client only reads via RLS.
// ---------------------------------------------------------------------------

app.post("/v1/friends/invite", requireUser, inviteByEmail);
app.post("/v1/invites", requireUser, createInviteLink);
app.post("/v1/invites/claim", requireUser, claimInvite);
// Unauthenticated: feeds the professormadrid.com invite landing page.
app.get("/v1/invites/:token/public", publicInviteInfo);

app.get("/v1/friends", requireUser, listFriends);
app.post("/v1/friends/:id/accept", requireUser, respondToInvite(true));
app.post("/v1/friends/:id/decline", requireUser, respondToInvite(false));
app.delete("/v1/friends/:id", requireUser, unfriend);
app.post("/v1/blocks", requireUser, blockUser);
app.delete("/v1/blocks/:userId", requireUser, unblockUser);

app.post("/v1/songs/share", requireUser, shareSong);
app.get("/v1/songs/shared", requireUser, listSharedSongs);
app.post("/v1/songs/shared/:shareId/download", requireUser, downloadSharedSong);

app.post("/v1/admin/announcements", requireAdmin, createAnnouncement);
app.post("/v1/admin/announcements/:id/announce", requireAdmin, announceAnnouncement);
app.post("/v1/admin/announcements/:id/retire", requireAdmin, retireAnnouncement);
app.post("/v1/admin/announcements/:id/acks", requireAdmin, bulkAckAnnouncement);

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

app.post("/v1/roleplay-chat", requireUser, async (req, res) => {
  if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });

  const { systemPrompt, history, userText, maxTokens, isRetry } = req.body || {};
  const model = config.models.chat;
  const reason = "roleplay_turn";
  // The client silently retries once, invisibly to the user, when a round's
  // model output leaves one of the two AI voices asking the other a question
  // with no way for it to ever get answered (there's no "continue without a
  // new user message" mechanism) — that's our own reliability gap, not a
  // second turn the user asked for, so it isn't billed.
  const cost = isRetry ? 0 : config.actionCosts.roleplay;

  const pre = cost > 0 ? await debit(req.user.id, cost, reason, { model }) : { ok: true, enforced: false };
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  try {
    const result = await openaiChat({ systemPrompt, history, userText, maxTokens, model });
    const rawCost = chatCostUsd(result.usage.inputTokens, result.usage.outputTokens);
    await record({
      userId: req.user.id,
      kind: "roleplay",
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
  const validContexts = new Set(["scene","label","loro","encouragement","sentence","default","roleplay","onboarding"]);
  const context = (typeof req.body?.context === "string" && validContexts.has(req.body.context))
    ? req.body.context : "default";
  const voiceOverride = (req.body?.voice && typeof req.body.voice === "object")
    ? {
        languageCode: typeof req.body.voice.languageCode === "string" ? req.body.voice.languageCode : undefined,
        voiceName: typeof req.body.voice.voiceName === "string" ? req.body.voice.voiceName : undefined
      }
    : null;
  // Callers with pre-generated, pre-warmed-cache content (Say It Better's
  // explanation script) request strict voice consistency: no OpenAI
  // fallback, ever, even on a Cloud TTS + Gemini outage — a different voice
  // appearing mid-message is worse than that one clip staying silent. This
  // should be a near-dead code path in practice (the pre-warm script means a
  // real request almost always hits the cache above `getVoice`'s own
  // synthesizeVoice call), so a failure here is a real signal something
  // needs attention, not an expected runtime condition. Defaults true so
  // every other existing caller (regular chat, roleplay, onboarding, lesson
  // feedback/Q&A) is unaffected.
  const allowOpenAIFallback = req.body?.allowOpenAIFallback !== false;

  // Roleplay turns are billed as one flat charge on /v1/roleplay-chat that
  // already covers both persona voices for that turn — don't double-charge here.
  // Onboarding quiz audio is a free preview (the user hasn't even seen their
  // trial balance yet) — falling back to dynamic TTS for a missing bundled
  // asset shouldn't silently drain treats before the app is even set up.
  const cost = (context === "roleplay" || context === "onboarding") ? 0 : config.actionCosts.voice;
  let pre = { ok: true, enforced: false };
  if (cost > 0) {
    pre = await debit(req.user.id, cost, "voice_message", {});
    if (!pre.ok && pre.error === "insufficient_treats") {
      return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
    }
  }

  const audio = await getVoice(text, { format, context, voiceOverride, allowOpenAIFallback });
  if (!audio) {
    if (pre.enforced) await credit(req.user.id, cost, "refund", "voice_message_failed", {});
    if (!allowOpenAIFallback) {
      console.error(`[TTS] STRICT-VOICE FAILURE — no fallback allowed and Cloud TTS + Gemini both failed. context=${context} textPreview="${text.slice(0, 60)}"`);
    }
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
  const { prompt, kind, maxTokens, temperature } = req.body || {};
  if (!prompt || typeof prompt !== "string") return res.status(400).json({ error: "missing_prompt" });

  try {
    let result, rawCost, provider;

    if (kind === "roleplay_turn") {
      // Roleplay's per-message turn-taking referee: tiny, very frequent
      // (fires after every single message), so it runs on Google's cheapest
      // text tier instead of OpenAI. geminiText() also forces valid JSON via
      // responseMimeType, removing the code-fence/preamble parse failures an
      // OpenAI completion could return under this instruction.
      if (!config.geminiKey) return res.status(503).json({ error: "chat_not_configured" });
      result = await geminiText({
        prompt,
        model: config.models.turnClassifier,
        maxOutputTokens: maxTokens || 40,
        temperature: temperature ?? 0
      });
      rawCost = geminiLiteCostUsd(result.usage.inputTokens, result.usage.outputTokens);
      provider = "gemini";
    } else {
      if (!config.openaiKey) return res.status(503).json({ error: "chat_not_configured" });
      const model = kind === "analyst" ? config.models.analyst : config.models.chat;
      result = await openaiChat({
        userText: prompt,
        model,
        maxTokens: maxTokens || 256,
        temperature: temperature ?? 0
      });
      rawCost = kind === "analyst"
        ? analystCostUsd(result.usage.inputTokens, result.usage.outputTokens)
        : chatCostUsd(result.usage.inputTokens, result.usage.outputTokens);
      provider = "openai";
    }

    await record({
      userId: req.user.id,
      kind: "utility",
      provider,
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

  // Kick off the memorization illustration CONCURRENTLY with audio. It is a
  // best-effort extra (getIllustration never throws / returns null on failure),
  // so audio never waits on it and an image failure never refunds or fails.
  const illustrationPromise = getIllustration(script.spanish, script.english).catch(() => null);

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

  // Audio is done; fold in the illustration (already generating). Only bill raw
  // image cost for a fresh (non-cached) generation.
  const illustration = await illustrationPromise;
  const imageRawCost = illustration && !illustration.cached ? imageCostUsd(1) : 0;

  await record({
    userId: req.user.id,
    kind: "loro",
    provider,
    seconds: totalSeconds,
    rawCostUsd: ttsCostUsd(provider, billedSeconds) + imageRawCost,
    treatsCharged: cost
  });

  res.json({
    spanish: script.spanish,
    english: script.english,
    sentence1: script.sentence1,
    sentence2: script.sentence2,
    segments,
    ...(illustration ? { illustrationBase64: illustration.base64, illustrationMime: illustration.mime } : {}),
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

  // Best-effort illustration, generated CONCURRENTLY with the audio segments.
  // Never blocks playback; emitted as its own NDJSON event whenever it lands.
  const illustrationPromise = getIllustration(script.spanish, script.english).catch(() => null);

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

  // Emit the illustration once it resolves (audio already streamed). Best-effort:
  // a null result simply emits nothing and the client keeps the seagull pose.
  const illustration = await illustrationPromise;
  if (illustration) {
    write({ type: "illustration", base64: illustration.base64, mime: illustration.mime });
  }
  const imageRawCost = illustration && !illustration.cached ? imageCostUsd(1) : 0;

  const totalSeconds = segmentTexts.reduce((s, t) => s + Math.max(1, Math.round(t.length / 14)), 0);
  await record({
    userId: req.user.id,
    kind: "loro",
    provider,
    seconds: totalSeconds,
    rawCostUsd: ttsCostUsd(provider, billedSeconds) + imageRawCost,
    treatsCharged: cost
  });

  write({ type: "done", totalSeconds });
  res.end();
});

// On-demand illustration fetch/cache for an existing phrase. Free to call
// (no treat charge) because it wraps the same Supabase-cached Vertex path used
// inside /v1/loro/stream — a cache hit is instant and free; a miss generates
// one image and caches it for future calls. Returns { base64, mime } or 404
// when image generation is unavailable.
app.post("/v1/illustration", requireUser, async (req, res) => {
  const { spanish, english, scenePrompt } = req.body || {};

  if (typeof scenePrompt === "string" && scenePrompt.trim()) {
    const illustration = await getIllustrationFromPrompt(scenePrompt.trim()).catch(() => null);
    if (!illustration) {
      return res.status(404).json({ error: "illustration_unavailable" });
    }
    // scenePrompt-shaped requests are exclusively Roleplay scene backgrounds
    // (see ProxyClient.fetchRoleplayScene) — composite the Madrid mascot onto
    // every one of these so he's a consistent, recognizable presence in every
    // episode, without touching the shared illustration cache used by the
    // spanish/english (memorization) branch below.
    const composited = await compositeMascot(Buffer.from(illustration.base64, "base64")).catch(
      () => null
    );
    return res.json({
      base64: (composited || Buffer.from(illustration.base64, "base64")).toString("base64"),
      mime: "image/jpeg"
    });
  }

  if (!spanish || typeof spanish !== "string") {
    return res.status(400).json({ error: "missing_spanish" });
  }
  const illustration = await getIllustration(
    spanish,
    typeof english === "string" ? english : ""
  ).catch(() => null);
  if (!illustration) {
    return res.status(404).json({ error: "illustration_unavailable" });
  }
  res.json({ base64: illustration.base64, mime: illustration.mime });
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
    console.warn(`[TOPUP] user=${req.user.id} rejected: missing_signed_transaction`);
    return res.status(400).json({ error: "missing_signed_transaction" });
  }
  console.log(`[TOPUP] user=${req.user.id} received JWS, len=${signedTransaction.length}, segments=${signedTransaction.split(".").length}`);

  let payload;
  try {
    payload = verifyStoreKitJWS(signedTransaction);
  } catch (e) {
    console.error(`[TOPUP] user=${req.user.id} verification FAILED: ${e.message}`);
    return res.status(400).json({ error: "invalid_transaction", detail: e.message });
  }
  console.log(`[TOPUP] user=${req.user.id} verified OK: productId=${payload.productId} transactionId=${payload.transactionId} bundleId=${payload.bundleId}`);

  if (payload.bundleId !== config.appleBundleId) {
    console.error(`[TOPUP] user=${req.user.id} bundle_mismatch: got=${payload.bundleId} expected=${config.appleBundleId}`);
    return res.status(400).json({ error: "bundle_mismatch" });
  }

  const pack = config.packs[payload.productId];
  if (!pack) {
    console.error(`[TOPUP] user=${req.user.id} unknown_product: ${payload.productId}`);
    return res.status(400).json({ error: "unknown_product", productId: payload.productId });
  }

  const transactionId = String(payload.transactionId || "");
  if (!transactionId) {
    console.error(`[TOPUP] user=${req.user.id} missing_transaction_id`);
    return res.status(400).json({ error: "missing_transaction_id" });
  }

  const result = await recordTopup({
    userId: req.user.id,
    productId: payload.productId,
    usd: pack.usd,
    baseTreats: pack.baseTreats,
    bonusPct: pack.bonusPct,
    totalTreats: pack.totalTreats,
    transactionId
  });

  if (!result.ok) {
    console.error(`[TOPUP] user=${req.user.id} credit_failed: ${result.error}`);
    return res.status(502).json({ error: "credit_failed", detail: result.error });
  }
  console.log(`[TOPUP] user=${req.user.id} credited productId=${payload.productId} treats=${pack.totalTreats} duplicate=${Boolean(result.duplicate)}`);

  // Friends' activity feed ("X bought a pack") — detached, never blocks the purchase.
  if (!result.duplicate) fanOutPackPurchase(req.user.id, payload.productId);

  const wallet = await getWallet(req.user.id);
  res.json({ ...walletPayload(req.user.id, wallet), duplicate: Boolean(result.duplicate), creditedTreats: result.duplicate ? 0 : pack.totalTreats });
});


// Permanently delete the authenticated user's account and all associated data.
// Anonymises topups for financial audit trail, deletes everything else.
app.post("/v1/delete-account", requireUser, async (req, res) => {
  const sb = supabase();
  if (!sb) return res.status(503).json({ error: "wallet_not_configured" });

  const userId = req.user.id;

  const tables = ["messages", "sessions", "memory_cards", "analyst_events", "usage_meter", "wallets"];
  for (const table of tables) {
    await sb.from(table).delete().eq("user_id", userId);
  }

  await sb.from("topups").update({ user_id: null }).eq("user_id", userId);
  await sb.from("profiles").delete().eq("id", userId);

  const { error: authErr } = await sb.auth.admin.deleteUser(userId);
  if (authErr) {
    return res.status(502).json({ error: "auth_delete_failed", detail: authErr.message });
  }

  res.json({ deleted: true });
});

// ---------------------------------------------------------------------------
// Voice onboarding quiz — utility class, JWT-gated, not billed.
// The client walks the 11-question flow locally, hitting the two probe passes
// (Q8, Q9) mid-quiz and the synthesis pass at the end.
// ---------------------------------------------------------------------------

const ONBOARDING_LANGS = new Set(["en", "uk"]);
const ONBOARDING_PRONOUNS = new Set(["he", "she", "they"]);
const PROBE_SLOTS = new Set([
  "pet_name", "kid_name_or_age", "partner_name", "best_friend_name",
  "city_ritual", "hobby_detail", "daily_moment"
]);

function pickTranscripts(body) {
  const out = {};
  const src = body?.transcripts || {};
  for (const k of ["q1","q2","q3","q4","q5","q6","q7","q8","q9","q10","q11"]) {
    if (typeof src[k] === "string") out[k] = src[k].slice(0, 2000);
  }
  return out;
}

async function callProbe(prompt, res) {
  let raw;
  try {
    raw = await geminiText({
      prompt,
      model: config.models.onboardingProbe,
      temperature: 0.55,
      maxOutputTokens: 512
    });
  } catch (e) {
    return res.status(e.status || 502).json({ error: "probe_upstream", detail: e.message });
  }
  let parsed;
  try {
    parsed = JSON.parse(raw.text);
  } catch (_) {
    // One retry with lower temperature.
    try {
      const retry = await geminiText({
        prompt,
        model: config.models.onboardingProbe,
        temperature: 0.2,
        maxOutputTokens: 512
      });
      parsed = JSON.parse(retry.text);
    } catch (e) {
      return res.status(502).json({ error: "probe_invalid_json" });
    }
  }
  if (typeof parsed?.next_question_text !== "string" || !parsed.next_question_text.trim()) {
    return res.status(502).json({ error: "probe_missing_question" });
  }
  const slot = PROBE_SLOTS.has(parsed.target_slot) ? parsed.target_slot : "daily_moment";
  return res.json({
    nextQuestionText: parsed.next_question_text.trim(),
    targetSlot: slot,
    reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning : ""
  });
}

app.post("/v1/onboarding/probe", requireUser, async (req, res) => {
  const { pass, pronoun, quizLanguage, previousProbe } = req.body || {};
  console.log(`[onboarding/probe] user=${req.user.id} pass=${JSON.stringify(pass)} pronoun=${JSON.stringify(pronoun)} quizLanguage=${JSON.stringify(quizLanguage)}`);
  if (!ONBOARDING_PRONOUNS.has(pronoun)) return res.status(400).json({ error: "bad_pronoun", received: pronoun });
  if (!ONBOARDING_LANGS.has(quizLanguage)) return res.status(400).json({ error: "bad_language", received: quizLanguage });
  const transcripts = pickTranscripts(req.body);

  let prompt;
  if (pass === 1) {
    prompt = probePass1Prompt({ pronoun, quizLanguage, transcripts });
  } else if (pass === 2) {
    prompt = probePass2Prompt({
      pronoun, quizLanguage, transcripts,
      previousProbe: previousProbe && typeof previousProbe === "object" ? previousProbe : null
    });
  } else {
    return res.status(400).json({ error: "bad_pass" });
  }
  return callProbe(prompt, res);
});

app.post("/v1/onboarding/synthesize", requireUser, async (req, res) => {
  const { pronoun, quizLanguage, probes } = req.body || {};
  console.log(`[onboarding/synthesize] user=${req.user.id} pronoun=${JSON.stringify(pronoun)} quizLanguage=${JSON.stringify(quizLanguage)} probes=${JSON.stringify(probes)}`);
  if (!ONBOARDING_PRONOUNS.has(pronoun)) return res.status(400).json({ error: "bad_pronoun", received: pronoun });
  if (!ONBOARDING_LANGS.has(quizLanguage)) return res.status(400).json({ error: "bad_language", received: quizLanguage });
  const transcripts = pickTranscripts(req.body);

  const prompt = synthesisPrompt({
    pronoun,
    quizLanguage,
    transcripts,
    probes: probes && typeof probes === "object" ? probes : null
  });

  const callSynthesis = (temperature) => geminiText({
    prompt,
    model: config.models.onboardingSynthesis,
    temperature,
    // gemini-2.5-pro can't run with thinking disabled (see providers.js),
    // so reasoning tokens now eat into this budget too — bumped up from
    // 2048 for headroom.
    maxOutputTokens: 4096,
    disableThinking: false
  });

  let raw;
  try {
    raw = await callSynthesis(0.35);
    console.log(`[onboarding/synthesize] gemini responded, ${raw.text.length} chars, outputTokens=${raw.usage?.outputTokens}`);
  } catch (e) {
    console.error(`[onboarding/synthesize] gemini call failed: ${e.message}`);
    return res.status(e.status || 502).json({ error: "synthesis_upstream", detail: e.message });
  }

  let parsed;
  try { parsed = JSON.parse(raw.text); }
  catch (_) {
    // One retry at lower temperature — mirrors callProbe. A single malformed
    // Gemini response used to 502 straight to the client, whose old dead-end
    // .failed screen is what App Review saw as "app froze on the tutorial".
    console.error(`[onboarding/synthesize] JSON.parse failed, retrying once — raw text (first 500 chars): ${raw.text.slice(0, 500)}`);
    try {
      const retry = await callSynthesis(0.15);
      parsed = JSON.parse(retry.text);
      console.log(`[onboarding/synthesize] retry succeeded, ${retry.text.length} chars`);
    } catch (e2) {
      console.error(`[onboarding/synthesize] retry also failed: ${e2.message}`);
      return res.status(502).json({ error: "synthesis_invalid_json" });
    }
  }

  const required = ["tutor_cheat_sheet", "narrative_summary", "about_me_user_facing", "city_flavor", "extracted_slots"];
  for (const k of required) {
    if (!(k in parsed)) {
      console.error(`[onboarding/synthesize] missing key "${k}" — parsed keys: ${Object.keys(parsed).join(", ")}`);
      return res.status(502).json({ error: `synthesis_missing_${k}` });
    }
  }

  // level_breakdown is a v5 addition — normalise to a stable camelCase shape
  // so the client always gets the same schema even when Gemini omits it.
  const rawLB = (parsed.level_breakdown && typeof parsed.level_breakdown === "object")
    ? parsed.level_breakdown : {};
  const skill = (k) => {
    const s = rawLB[k] && typeof rawLB[k] === "object" ? rawLB[k] : {};
    return {
      band: String(s.band || "unknown"),
      note: String(s.note || "")
    };
  };
  const rawGoals = Array.isArray(rawLB.goals) ? rawLB.goals : [];
  const levelBreakdown = {
    overallBand: String(rawLB.overall_band || "unknown"),
    currentState: String(rawLB.current_state || ""),
    listening: skill("listening"),
    speaking: skill("speaking"),
    grammar: skill("grammar"),
    goals: rawGoals.map((g) => String(g || "")).filter(Boolean).slice(0, 6)
  };

  const synthesisRecord = {
    tutorCheatSheet: String(parsed.tutor_cheat_sheet || ""),
    narrativeSummary: String(parsed.narrative_summary || ""),
    aboutMeUserFacing: String(parsed.about_me_user_facing || ""),
    cityFlavor: String(parsed.city_flavor || ""),
    extractedSlots: parsed.extracted_slots || {},
    levelBreakdown,
    version: ONBOARDING_QUIZ_VERSION,
    voiceTag: activeVoiceTag()
  };

  // Persist server-side the moment it's computed — previously this was only
  // ever handed back to the client to save, so the backend never actually
  // remembered a user's onboarding profile. Best-effort: a failure here must
  // not block the response, since the client still persists its own copy.
  const sb = supabase();
  if (sb) {
    const { error } = await sb.from("onboarding_syntheses").upsert({
      user_id: req.user.id,
      quiz_version: synthesisRecord.version,
      pronoun,
      quiz_language: quizLanguage,
      tutor_cheat_sheet: synthesisRecord.tutorCheatSheet,
      narrative_summary: synthesisRecord.narrativeSummary,
      about_me_user_facing: synthesisRecord.aboutMeUserFacing,
      city_flavor: synthesisRecord.cityFlavor,
      extracted_slots: synthesisRecord.extractedSlots,
      level_breakdown: levelBreakdown,
      voice_tag: synthesisRecord.voiceTag,
      updated_at: new Date().toISOString()
    });
    if (error) {
      console.error("[onboarding/synthesize] failed to persist onboarding_syntheses:", error.message);
    } else {
      console.log("[onboarding/synthesize] persisted onboarding_syntheses ok");
    }
  }

  console.log(`[onboarding/synthesize] responding 200, user=${req.user.id}`);
  res.json(synthesisRecord);
});

app.get("/v1/voice/current", requireUser, (req, res) => {
  res.json({ voiceTag: activeVoiceTag() });
});

// Kick off a song generation job. Debits treats up front (refunded via the
// job's outcome callback if the pipeline fails), returns a jobId to poll.
app.post("/v1/music/generate", requireUser, async (req, res) => {
  if (!musicConfigured()) return res.status(503).json({ error: "music_not_configured" });

  const { genre, durationSec, lyrics, description, words, language } = req.body || {};
  if (!genre || typeof genre !== "string" || !genre.trim()) {
    return res.status(400).json({ error: "missing_genre" });
  }
  const duration = [30, 60, 120].includes(Number(durationSec)) ? Number(durationSec) : 30;
  const cleanWords = Array.isArray(words)
    ? words.filter(w => typeof w === "string" && w.trim()).map(w => w.trim()).slice(0, 30)
    : [];

  const cost = musicCostForDuration(duration);
  const pre = await debit(req.user.id, cost, "music_song", { genre: genre.trim(), durationSec: duration });
  if (!pre.ok && pre.error === "insufficient_treats") {
    return res.status(402).json({ error: "insufficient_treats", balance: pre.balance });
  }

  const job = startMusicJob({
    userId: req.user.id,
    genre: genre.trim().slice(0, 80),
    durationSec: duration,
    lyrics: typeof lyrics === "string" ? lyrics.slice(0, 4000) : "",
    description: typeof description === "string" ? description.slice(0, 2000) : "",
    words: cleanWords,
    language: language === "uk" ? "uk" : "en"
  }, async (outcome) => {
    if (outcome.ok) {
      // Rough per-song COGS placeholder until real GPU seconds are measured.
      await record({
        userId: req.user.id,
        kind: "music",
        provider: "ace-step",
        seconds: duration,
        rawCostUsd: 0.02 * (duration / 30),
        treatsCharged: cost
      });
    } else if (pre.enforced) {
      await credit(req.user.id, cost, "refund", "music_song_failed", {});
    }
  });

  // Cold Cloud Run instance loads the model first; warm ones answer fast.
  res.json({ jobId: job.id, treatsCharged: cost, etaSeconds: duration >= 120 ? 180 : 120 });
});

app.get("/v1/music/job/:id", requireUser, (req, res) => {
  const job = getMusicJob(req.params.id, req.user.id);
  if (!job) return res.status(404).json({ error: "job_not_found" });
  const payload = { jobId: job.id, status: job.status };
  if (job.status === "failed") payload.error = job.error || "generation_failed";
  if (job.status === "done" && job.song) payload.song = job.song;
  res.json(payload);
});

app.use((req, res) => res.status(404).json({ error: "not_found" }));

app.listen(config.port, () => {
  console.log(`professor-madrid-api listening on :${config.port}`);
});

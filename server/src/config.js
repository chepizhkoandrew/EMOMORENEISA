function num(name, fallback) {
  const v = process.env[name];
  if (v === undefined || v === "") return fallback;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function bool(name, fallback) {
  const v = process.env[name];
  if (v === undefined || v === "") return fallback;
  return v === "1" || v.toLowerCase() === "true" || v.toLowerCase() === "yes";
}

function str(name, fallback) {
  const v = process.env[name];
  return v === undefined || v === "" ? fallback : v;
}

// Google Cloud service-account JSON, shared by Cloud TTS and Vertex AI image
// generation. Provided raw via GOOGLE_TTS_CREDENTIALS or base64 via
// GOOGLE_TTS_CREDENTIALS_B64. Parsed once so both consumers use the same creds.
const cloudTtsCredentials = (() => {
  const rawB64 = process.env.GOOGLE_TTS_CREDENTIALS_B64;
  const raw = process.env.GOOGLE_TTS_CREDENTIALS;
  try {
    if (rawB64) return JSON.parse(Buffer.from(rawB64, "base64").toString("utf8"));
    if (raw) return JSON.parse(raw);
  } catch (e) {
    console.warn("[config] GOOGLE_TTS_CREDENTIALS parse failed:", e.message);
  }
  return null;
})();

export const config = {
  port: num("PORT", 8080),
  env: str("NODE_ENV", "production"),

  supabaseUrl: str("SUPABASE_URL", ""),
  supabaseServiceKey: str("SUPABASE_SERVICE_ROLE_KEY", ""),
  supabaseJwtSecret: str("SUPABASE_JWT_SECRET", ""),

  openaiKey: str("OPENAI_API_KEY", ""),
  geminiKey: str("GEMINI_API_KEY", ""),

  models: {
    chat: str("MODEL_CHAT", "gpt-4.1"),
    vision: str("MODEL_VISION", "gpt-4.1"),
    analyst: str("MODEL_ANALYST", "gpt-4o-mini"),
    // NOTE: every Gemini TTS model on the generativelanguage API is Preview-only
    // (flash-preview-tts, pro-preview-tts, 3.1-flash-tts-preview). Google
    // documents that these models randomly return text instead of audio -> HTTP
    // 500, which is the root cause of our intermittent 502s. There is no GA
    // Gemini TTS on this endpoint (the GA gemini-*-tts models live on Cloud TTS,
    // which needs service-account auth). Hence the OpenAI fallback below.
    ttsGemini: str("MODEL_TTS_GEMINI", "gemini-2.5-flash-preview-tts"),
    // Secondary Gemini attempt before falling back to OpenAI. Defaults to the
    // same flash model; point at another Gemini TTS model to switch.
    ttsGeminiFallback: str("MODEL_TTS_GEMINI_FALLBACK", "gemini-2.5-flash-preview-tts"),
    // Multilingual OpenAI voice model — officially supports Spanish with
    // native-level pronunciation (50+ languages), so this is a first-class
    // fallback, not a degraded English-accent stopgap. Used whenever the preview
    // Gemini model fails so audio is never silent.
    ttsOpenAI: str("MODEL_TTS_OPENAI", "gpt-4o-mini-tts"),
    // OpenAI speech-to-text. gpt-4o-transcribe is the most accurate for catching
    // Spanish word endings (the part that matters most for the verb game).
    transcribe: str("MODEL_TRANSCRIBE", "gpt-4o-transcribe"),
    // Onboarding reasoning models — Gemini text via generativelanguage API.
    // Probes run mid-quiz (must be quick); synthesis runs once at the end.
    onboardingProbe: str("MODEL_ONBOARDING_PROBE", "gemini-2.5-flash"),
    onboardingSynthesis: str("MODEL_ONBOARDING_SYNTHESIS", "gemini-2.5-pro")
  },

  // Voice synthesis behaviour. Spanish audio must stay on Gemini; the OpenAI
  // engine speaks Spanish text with an English accent, so it is OFF by default
  // and only ever used if a deploy explicitly opts in for English-only text.
  tts: {
    voiceName: str("TTS_GEMINI_VOICE", "Charon"),
    retries: num("TTS_RETRIES", 3),
    retryBaseMs: num("TTS_RETRY_BASE_MS", 600),
    loroConcurrency: num("LORO_TTS_CONCURRENCY", 2),
    // Gemini TTS is a preview-only model with a tight per-minute request cap and
    // intermittent empty responses. Fall back to OpenAI's multilingual voice
    // (good native Spanish) so audio is never silent. Set false to force Gemini.
    allowOpenAIFallback: bool("TTS_ALLOW_OPENAI_FALLBACK", true),
    openaiVoice: str("TTS_OPENAI_VOICE", "onyx")
  },

  // Google Cloud Text-to-Speech (GA). Unlike the Gemini generativelanguage TTS
  // models (all Preview-only, randomly drop audio -> 502s), Cloud TTS ships GA
  // "Chirp 3: HD" Spanish voices that are reliable and natural. It uses a
  // service account (OAuth2), not the simple API key, so credentials are the
  // full service-account JSON, provided raw via GOOGLE_TTS_CREDENTIALS or
  // base64 via GOOGLE_TTS_CREDENTIALS_B64. When credentials are present this
  // becomes the PRIMARY voice engine (Gemini/OpenAI remain as fallbacks).
  cloudTts: (() => {
    const credentials = cloudTtsCredentials;
    return {
      credentials,
      enabled: bool("CLOUD_TTS_ENABLED", !!credentials),
      // es-ES = Spain (Castilian), es-US = Latin American. Professor Madrid -> es-ES.
      languageCode: str("CLOUD_TTS_LANGUAGE", "es-ES"),
      // Chirp 3 HD voice. Format: {locale}-Chirp3-HD-{Name}. Achird is a warm male voice.
      voiceName: str("CLOUD_TTS_VOICE", "es-ES-Chirp3-HD-Achird"),
      // 1.0 = normal speed, 0.9 = slightly slower (better for language learning).
      speakingRate: num("CLOUD_TTS_SPEAKING_RATE", 0.9)
    };
  })(),

  // Shared, deduplicated voice cache. Generated audio is transcoded to AAC and
  // stored in Supabase Storage keyed by hash(model+voice+bitrate+text), so the
  // same phrase is only ever synthesized once across ALL users. Cache hits skip
  // Gemini entirely (avoids its ~10 RPM limit) and ship a much smaller payload.
  audio: {
    cacheEnabled: bool("AUDIO_CACHE_ENABLED", true),
    bucket: str("AUDIO_CACHE_BUCKET", "voice-cache"),
    aacBitrate: str("AAC_BITRATE", "40k")
  },

  // Vertex AI image generation (Gemini 2.5 Flash Image, aka "nano banana").
  // Runs on Google Cloud with the SAME service account as Cloud TTS (Vertex AI
  // must be enabled on it) — NOT the generativelanguage API key — so the
  // memorization-illustration generator does not share the rate-limited preview
  // endpoint. Project id is read from the service-account JSON unless overridden.
  vertexImage: (() => {
    const credentials = cloudTtsCredentials;
    const projectId = str("VERTEX_PROJECT_ID", credentials?.project_id || "");
    return {
      credentials,
      projectId,
      // "global" uses aiplatform.googleapis.com; a region uses {loc}-aiplatform.
      location: str("VERTEX_LOCATION", "global"),
      model: str("VERTEX_IMAGE_MODEL", "gemini-2.5-flash-image"),
      enabled: bool("VERTEX_IMAGE_ENABLED", !!credentials && !!projectId)
    };
  })(),

  // Shared, deduplicated illustration cache (mirrors the voice cache). Generated
  // images are transcoded to small JPEGs and stored in Supabase Storage keyed by
  // hash(model+style-version+prompt) so a phrase is only ever illustrated once
  // across ALL users. Cache hits skip Vertex entirely.
  image: {
    cacheEnabled: bool("IMAGE_CACHE_ENABLED", true),
    bucket: str("IMAGE_CACHE_BUCKET", "image-cache"),
    jpegQuality: num("IMAGE_JPEG_QUALITY", 82),
    maxSize: num("IMAGE_MAX_SIZE", 512)
  },

  // Self-hosted song generation (ACE-Step on Cloud Run GPU, scale-to-zero —
  // the instance spins up per request and bills only generation seconds, so
  // "off" is the default state and needs no manual switching).
  music: {
    serviceUrl: str("MUSIC_SERVICE_URL", ""),
    serviceKey: str("MUSIC_SERVICE_KEY", ""),
    lyricsModel: str("MODEL_MUSIC_LYRICS", "gemini-2.5-flash"),
    // Cold start (model load) + generation can take minutes; the proxy->GPU
    // call needs real headroom. The client polls, so nothing user-facing
    // hangs on this.
    requestTimeoutMs: num("MUSIC_REQUEST_TIMEOUT_MS", 600000)
  },

  enforceWallet: bool("ENFORCE_WALLET", false),

  // Social layer: friend invites, song sharing, in-app notifications.
  social: {
    // Base for shareable invite links; the website rewrites /invite/:token.
    inviteBaseUrl: str("INVITE_BASE_URL", "https://professormadrid.com/invite"),
    // Origin allowed to call the public invite-info endpoint.
    corsOrigin: str("INVITE_CORS_ORIGIN", "https://professormadrid.com"),
    // Private bucket for shared song mp3s (content-addressed, deduped).
    songBucket: str("SHARED_SONG_BUCKET", "shared-songs"),
    // Shared secret for /v1/admin/* announcement endpoints. Unset = admin
    // surface disabled (503).
    adminApiKey: str("ADMIN_API_KEY", "")
  },

  // Apple / StoreKit
  appleBundleId: str("APPLE_BUNDLE_ID", "com.professormadrid.app"),
  trialGrantTreats: num("TRIAL_GRANT_TREATS", 150),

  // Consumable treat packs (product_id -> grant). bonus_pct is informational;
  // total_treats is what actually gets credited. Override via PACKS_JSON env.
  packs: (() => {
    const raw = process.env.PACKS_JSON;
    if (raw) {
      try { return JSON.parse(raw); } catch (_) { /* fall through to default */ }
    }
    return {
      treats_starter_599:  { usd: 5.99,  baseTreats: 599,  bonusPct: 0,  totalTreats: 599 },
      treats_plus_1199:    { usd: 11.99, baseTreats: 1199, bonusPct: 15, totalTreats: 1379 },
      treats_pro_2499:     { usd: 24.99, baseTreats: 2499, bonusPct: 25, totalTreats: 3124 }
    };
  })(),

  // Flat per-action treat costs (simple, predictable for users). The real COGS is
  // still measured and stored in usage_meter so margin can be monitored.
  actionCosts: {
    chat: num("COST_CHAT_MESSAGE", 5),
    voice: num("COST_VOICE_MESSAGE", 2),
    streetView: num("COST_STREET_VIEW", 9),
    loro: num("COST_LORO_DRILL", 3),
    annotate: num("COST_ANNOTATE", 6),
    verbCheck: num("COST_VERB_CHECK", 2),
    // Flat charge per roleplay turn — covers the larger dual-persona completion
    // plus both subsequent TTS calls (Madrid + object), which are billed free
    // via the "roleplay" TTS context so a turn is never double-charged.
    roleplay: num("COST_ROLEPLAY_TURN", 12),
    // Placeholder song prices until real GPU cost per length is measured.
    musicShort: num("COST_MUSIC_30S", 15),
    musicMedium: num("COST_MUSIC_60S", 25),
    musicLong: num("COST_MUSIC_120S", 45)
  },

  pricing: {
    usdPerMTokInChat: num("USD_PER_MTOK_IN_CHAT", 2.0),
    usdPerMTokOutChat: num("USD_PER_MTOK_OUT_CHAT", 8.0),
    usdPerMTokInAnalyst: num("USD_PER_MTOK_IN_ANALYST", 0.15),
    usdPerMTokOutAnalyst: num("USD_PER_MTOK_OUT_ANALYST", 0.6),
    usdPerMinTtsGemini: num("USD_PER_MIN_TTS_GEMINI", 0.0048),
    usdPerMinTtsOpenAI: num("USD_PER_MIN_TTS_OPENAI", 0.015),
    // Vertex Gemini 2.5 Flash Image bills ~1290 output tokens/image (~$0.039).
    usdPerImage: num("USD_PER_IMAGE", 0.039),
    infraOverhead: num("INFRA_OVERHEAD", 0.15),
    targetMargin: num("TARGET_MARGIN", 5.0),
    appleFee: num("APPLE_FEE", 0.15),
    usdPerTreat: num("USD_PER_TREAT", 0.01),
    streetViewFreePerDay: num("STREETVIEW_FREE_PER_DAY", 20),
    trialBudgetUsd: num("TRIAL_BUDGET_USD", 0.05)
  },

  limits: {
    perUserDailyUsd: num("CIRCUIT_PER_USER_DAILY_USD", 5.0),
    globalDailyUsd: num("CIRCUIT_GLOBAL_DAILY_USD", 200.0)
  }
};

export function featureFlags() {
  return {
    chat: Boolean(config.openaiKey),
    tts: Boolean(config.geminiKey || config.openaiKey),
    wallet: Boolean(config.supabaseUrl && config.supabaseServiceKey),
    auth: Boolean(config.supabaseUrl && config.supabaseServiceKey)
  };
}

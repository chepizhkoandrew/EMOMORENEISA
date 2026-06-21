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
    ttsGemini: str("MODEL_TTS_GEMINI", "gemini-2.5-flash-preview-tts"),
    // Fallback is ALSO Gemini (never a different-language engine). By default it
    // retries the same flash model; set to another Gemini TTS model to switch.
    ttsGeminiFallback: str("MODEL_TTS_GEMINI_FALLBACK", "gemini-2.5-flash-preview-tts"),
    ttsOpenAI: str("MODEL_TTS_OPENAI", "tts-1")
  },

  // Voice synthesis behaviour. Spanish audio must stay on Gemini; the OpenAI
  // engine speaks Spanish text with an English accent, so it is OFF by default
  // and only ever used if a deploy explicitly opts in for English-only text.
  tts: {
    voiceName: str("TTS_GEMINI_VOICE", "Charon"),
    retries: num("TTS_RETRIES", 3),
    retryBaseMs: num("TTS_RETRY_BASE_MS", 600),
    loroConcurrency: num("LORO_TTS_CONCURRENCY", 2),
    allowOpenAIFallback: bool("TTS_ALLOW_OPENAI_FALLBACK", false)
  },

  // Shared, deduplicated voice cache. Generated audio is transcoded to AAC and
  // stored in Supabase Storage keyed by hash(model+voice+bitrate+text), so the
  // same phrase is only ever synthesized once across ALL users. Cache hits skip
  // Gemini entirely (avoids its ~10 RPM limit) and ship a much smaller payload.
  audio: {
    cacheEnabled: bool("AUDIO_CACHE_ENABLED", true),
    bucket: str("AUDIO_CACHE_BUCKET", "voice-cache"),
    aacBitrate: str("AAC_BITRATE", "40k")
  },

  enforceWallet: bool("ENFORCE_WALLET", false),

  // Apple / StoreKit
  appleBundleId: str("APPLE_BUNDLE_ID", "com.professormadrid.app"),
  trialGrantTreats: num("TRIAL_GRANT_TREATS", 50),

  // Consumable treat packs (product_id -> grant). bonus_pct is informational;
  // total_treats is what actually gets credited. Override via PACKS_JSON env.
  packs: (() => {
    const raw = process.env.PACKS_JSON;
    if (raw) {
      try { return JSON.parse(raw); } catch (_) { /* fall through to default */ }
    }
    return {
      treats_599:  { usd: 5.99,  baseTreats: 599,  bonusPct: 0,  totalTreats: 599 },
      treats_1199: { usd: 11.99, baseTreats: 1199, bonusPct: 15, totalTreats: 1379 },
      treats_2499: { usd: 24.99, baseTreats: 2499, bonusPct: 25, totalTreats: 3124 },
      treats_4999: { usd: 49.99, baseTreats: 4999, bonusPct: 48, totalTreats: 7399 }
    };
  })(),

  // Flat per-action treat costs (simple, predictable for users). The real COGS is
  // still measured and stored in usage_meter so margin can be monitored.
  actionCosts: {
    chat: num("COST_CHAT_MESSAGE", 5),
    voice: num("COST_VOICE_MESSAGE", 2),
    streetView: num("COST_STREET_VIEW", 9),
    loro: num("COST_LORO_DRILL", 3)
  },

  pricing: {
    usdPerMTokInChat: num("USD_PER_MTOK_IN_CHAT", 2.0),
    usdPerMTokOutChat: num("USD_PER_MTOK_OUT_CHAT", 8.0),
    usdPerMTokInAnalyst: num("USD_PER_MTOK_IN_ANALYST", 0.15),
    usdPerMTokOutAnalyst: num("USD_PER_MTOK_OUT_ANALYST", 0.6),
    usdPerMinTtsGemini: num("USD_PER_MIN_TTS_GEMINI", 0.0048),
    usdPerMinTtsOpenAI: num("USD_PER_MIN_TTS_OPENAI", 0.015),
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

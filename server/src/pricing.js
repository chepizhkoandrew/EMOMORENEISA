import { config } from "./config.js";

export function chatCostUsd(inputTokens, outputTokens) {
  const p = config.pricing;
  return (
    (inputTokens / 1_000_000) * p.usdPerMTokInChat +
    (outputTokens / 1_000_000) * p.usdPerMTokOutChat
  );
}

export function analystCostUsd(inputTokens, outputTokens) {
  const p = config.pricing;
  return (
    (inputTokens / 1_000_000) * p.usdPerMTokInAnalyst +
    (outputTokens / 1_000_000) * p.usdPerMTokOutAnalyst
  );
}

export function geminiLiteCostUsd(inputTokens, outputTokens) {
  const p = config.pricing;
  return (
    (inputTokens / 1_000_000) * p.usdPerMTokInGeminiLite +
    (outputTokens / 1_000_000) * p.usdPerMTokOutGeminiLite
  );
}

export function ttsCostUsd(provider, seconds) {
  const p = config.pricing;
  const perMin = provider === "openai" ? p.usdPerMinTtsOpenAI : p.usdPerMinTtsGemini;
  return (seconds / 60) * perMin;
}

export function imageCostUsd(count) {
  return Math.max(0, count) * config.pricing.usdPerImage;
}

export function loadedCostUsd(rawCostUsd) {
  return rawCostUsd * (1 + config.pricing.infraOverhead);
}

export function retailUsd(rawCostUsd) {
  const p = config.pricing;
  const loadedWithMargin = loadedCostUsd(rawCostUsd) * p.targetMargin;
  return loadedWithMargin / (1 - p.appleFee);
}

export function usdToTreats(usd) {
  return Math.ceil(usd / config.pricing.usdPerTreat);
}

export function treatsForRawCost(rawCostUsd) {
  return usdToTreats(retailUsd(rawCostUsd));
}

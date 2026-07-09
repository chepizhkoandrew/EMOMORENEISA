// Self-test for the memorization-illustration generator. Confirms that Vertex
// AI (nano-banana / gemini-2.5-flash-image) is reachable with the SAME Cloud
// TTS service account BEFORE deploying, so we never ship a build whose images
// silently fall back to the seagull.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/test_illustration.mjs
//   railway run --service api node scripts/test_illustration.mjs "hola" "hello"
//
// Prints the resolved Vertex config, whether generation succeeded, and writes
// the produced image to /tmp so it can be eyeballed for style/quality.

import { writeFileSync } from "node:fs";
import { config } from "../src/config.js";
import { buildIllustrationPrompt } from "../src/providers.js";
import { getIllustration } from "../src/imagecache.js";

const spanish = process.argv[2] || "el gato duerme";
const english = process.argv[3] || "the cat sleeps";

const cfg = config.vertexImage;
console.log("[test] vertexImage config:", {
  enabled: cfg.enabled,
  projectId: cfg.projectId || "(none)",
  location: cfg.location,
  model: cfg.model,
  hasCredentials: !!cfg.credentials
});
console.log("[test] image cache:", {
  cacheEnabled: config.image.cacheEnabled,
  bucket: config.image.bucket
});

if (!cfg.enabled || !cfg.projectId) {
  console.error("[test] FAIL: Vertex image generation is disabled (missing credentials or project id).");
  process.exit(2);
}

console.log(`\n[test] prompt for "${spanish}" / "${english}":\n---\n${buildIllustrationPrompt(spanish, english)}\n---\n`);

const t0 = Date.now();
const result = await getIllustration(spanish, english);
const ms = Date.now() - t0;

if (!result?.base64) {
  console.error(`[test] FAIL: no illustration returned after ${ms}ms (Vertex unreachable / not enabled / quota).`);
  process.exit(1);
}

const ext = (result.mime || "image/jpeg").includes("png") ? "png" : "jpg";
const out = `/tmp/illustration_test.${ext}`;
writeFileSync(out, Buffer.from(result.base64, "base64"));
console.log(`[test] OK in ${ms}ms — mime=${result.mime} cached=${result.cached} bytes=${Buffer.from(result.base64, "base64").length}`);
console.log(`[test] wrote ${out}`);

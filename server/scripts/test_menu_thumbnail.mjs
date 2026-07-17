// One-off test generator for the new menu-card thumbnails, matching the
// existing btn_eye_see / btn_parrot_brain art style (bold flat vector icon,
// navy card background) rather than the ILLUSTRATION_STYLE_ANCHOR used for
// memorization-phrase illustrations elsewhere in the app.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/test_menu_thumbnail.mjs

import { writeFileSync } from "node:fs";
import { config } from "../src/config.js";
import { generateIllustration } from "../src/providers.js";

const MENU_THUMBNAIL_STYLE =
  "Flat vector icon illustration, bold clean thick outlines (like a modern " +
  "app icon), centered square composition on a solid deep navy-blue " +
  "background (#0f1a30). Warm golden-yellow and amber as the dominant " +
  "accent color, with crisp white highlights and small sparkle/glow " +
  "accents for a playful, energetic feel. One single bold, clearly " +
  "readable central subject filling most of the frame, no clutter, no " +
  "gradients besides simple cel-shading. Absolutely no text, letters, " +
  "numbers, or words anywhere in the image.";

const prompt =
  `${MENU_THUMBNAIL_STYLE}\n\n` +
  "Subject: two colorful overlapping speech bubbles, one with a small " +
  "sound-wave squiggle inside it, conveying an animated spoken conversation.";

const cfg = config.vertexImage;
console.log("[test] vertexImage config:", {
  enabled: cfg.enabled,
  projectId: cfg.projectId || "(none)",
  location: cfg.location,
  model: cfg.model,
  hasCredentials: !!cfg.credentials
});

if (!cfg.enabled || !cfg.projectId) {
  console.error("[test] FAIL: Vertex image generation is disabled (missing credentials or project id).");
  process.exit(2);
}

console.log(`\n[test] prompt:\n---\n${prompt}\n---\n`);

const t0 = Date.now();
const result = await generateIllustration(prompt);
const ms = Date.now() - t0;

if (!result?.base64) {
  console.error(`[test] FAIL: no illustration returned after ${ms}ms (Vertex unreachable / not enabled / quota).`);
  process.exit(1);
}

const ext = (result.mime || "image/png").includes("png") ? "png" : "jpg";
const outPath = `/tmp/menu_thumbnail_speaking_test.${ext}`;
writeFileSync(outPath, Buffer.from(result.base64, "base64"));
console.log(`[test] OK in ${ms}ms — wrote ${outPath} (mime=${result.mime})`);

// Generates the Role Play icon that was missed in the first batch.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/gen_roleplay_icon.mjs

import { writeFileSync } from "node:fs";
import { config } from "../src/config.js";
import { generateIllustration } from "../src/providers.js";

const TRANSPARENT_ICON_STYLE =
  "Flat vector icon illustration, bold clean thick outlines, warm " +
  "golden-yellow and amber as the dominant color for the subject, with " +
  "crisp white highlights and small sparkle/glow accents for a playful, " +
  "energetic feel, simple cel-shading only. The image MUST have a FULLY " +
  "TRANSPARENT background — no background color, no backdrop, no scene, " +
  "no ground, no shadow cast on anything behind it. Just the isolated " +
  "subject alone on alpha transparency, like a professional die-cut " +
  "sticker or app-icon asset exported as a transparent PNG. Centered " +
  "square composition, subject filling most of the frame. Absolutely no " +
  "text, letters, numbers, or words anywhere in the image.";

const prompt =
  `${TRANSPARENT_ICON_STYLE}\n\n` +
  "Subject: a pair of classic theater masks (one smiling, one with a " +
  "different playful expression) slightly overlapping, with small sparkle " +
  "accents, conveying role-play and imagination.";

const cfg = config.vertexImage;
if (!cfg.enabled || !cfg.projectId) {
  console.error("[roleplay] FAIL: Vertex image generation is disabled.");
  process.exit(2);
}

const t0 = Date.now();
const result = await generateIllustration(prompt);
const ms = Date.now() - t0;

if (!result?.base64) {
  console.error(`[roleplay] FAIL: no illustration returned after ${ms}ms.`);
  process.exit(1);
}

const ext = (result.mime || "image/png").includes("png") ? "png" : "jpg";
const outPath = `/tmp/menu_icon_role_play_raw.${ext}`;
writeFileSync(outPath, Buffer.from(result.base64, "base64"));
console.log(`[roleplay] OK in ${ms}ms — wrote ${outPath}`);

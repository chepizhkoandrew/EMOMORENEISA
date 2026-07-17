// Second attempt at the menu-card thumbnail style, forcing a true full-bleed
// edge-to-edge navy square (no rounded "app icon" card framing, no margin,
// no drop shadow) to match btn_eye_see.png / btn_parrot_brain.png exactly —
// both are opaque RGB with navy touching all four corners (~RGB 15,35,60).
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/test_menu_thumbnail2.mjs

import { writeFileSync } from "node:fs";
import { config } from "../src/config.js";
import { generateIllustration } from "../src/providers.js";

const MENU_THUMBNAIL_STYLE =
  "Flat vector icon illustration. The background is a SOLID FLAT dark navy " +
  "blue (RGB approximately 15, 35, 60) that fills the ENTIRE image edge to " +
  "edge, corner to corner, with ZERO margin, ZERO rounded corners, ZERO " +
  "border, ZERO drop shadow, and ZERO card/icon framing device — the navy " +
  "color must touch all four sides of the frame directly, like a plain " +
  "solid-color poster background, NOT like an app icon on a white canvas. " +
  "Bold clean thick outlines, warm golden-yellow and amber as the dominant " +
  "accent color for the subject, with crisp white highlights and small " +
  "sparkle/glow accents for a playful, energetic feel. One single bold, " +
  "clearly readable central subject filling most of the frame, no clutter, " +
  "simple cel-shading only. Centered square composition. Absolutely no " +
  "text, letters, numbers, or words anywhere in the image.";

const prompt =
  `${MENU_THUMBNAIL_STYLE}\n\n` +
  "Subject: two colorful overlapping speech bubbles, one with a small " +
  "sound-wave squiggle inside it, conveying an animated spoken conversation.";

const cfg = config.vertexImage;
console.log("[test2] vertexImage config:", {
  enabled: cfg.enabled,
  projectId: cfg.projectId || "(none)",
  location: cfg.location,
  model: cfg.model
});

if (!cfg.enabled || !cfg.projectId) {
  console.error("[test2] FAIL: Vertex image generation is disabled.");
  process.exit(2);
}

console.log(`\n[test2] prompt:\n---\n${prompt}\n---\n`);

const t0 = Date.now();
const result = await generateIllustration(prompt);
const ms = Date.now() - t0;

if (!result?.base64) {
  console.error(`[test2] FAIL: no illustration returned after ${ms}ms.`);
  process.exit(1);
}

const ext = (result.mime || "image/png").includes("png") ? "png" : "jpg";
const outPath = `/tmp/menu_thumbnail_speaking_test2.${ext}`;
writeFileSync(outPath, Buffer.from(result.base64, "base64"));
console.log(`[test2] OK in ${ms}ms — wrote ${outPath} (mime=${result.mime})`);

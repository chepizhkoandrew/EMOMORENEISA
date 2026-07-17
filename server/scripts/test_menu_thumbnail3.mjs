// Third attempt: true transparent-background icons (alpha PNG), replacing
// the opaque-navy-square approach entirely. Generates both an "eye" and a
// "parrot brain" icon as replacements for btn_eye_see.png / btn_parrot_brain.png
// so every menu thumbnail can share one transparent-background pipeline and
// float on whatever card background the app uses, instead of baking in a
// fixed navy color.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/test_menu_thumbnail3.mjs

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

const subjects = [
  {
    name: "eye",
    text: "A single stylized wide-open human eye with a detailed iris and " +
      "pupil, eyelashes, like a vision/camera-focus icon."
  },
  {
    name: "parrot_brain",
    text: "A colorful cartoon parrot perched and alert, with a small " +
      "glowing brain icon visible above/on its head, conveying " +
      "intelligence and learning."
  }
];

const cfg = config.vertexImage;
console.log("[test3] vertexImage config:", {
  enabled: cfg.enabled,
  projectId: cfg.projectId || "(none)",
  location: cfg.location,
  model: cfg.model
});

if (!cfg.enabled || !cfg.projectId) {
  console.error("[test3] FAIL: Vertex image generation is disabled.");
  process.exit(2);
}

for (const subject of subjects) {
  const prompt = `${TRANSPARENT_ICON_STYLE}\n\nSubject: ${subject.text}`;
  console.log(`\n[test3] === ${subject.name} ===`);
  console.log(`[test3] prompt:\n---\n${prompt}\n---\n`);

  const t0 = Date.now();
  const result = await generateIllustration(prompt);
  const ms = Date.now() - t0;

  if (!result?.base64) {
    console.error(`[test3] FAIL (${subject.name}): no illustration returned after ${ms}ms.`);
    continue;
  }

  const ext = (result.mime || "image/png").includes("png") ? "png" : "jpg";
  const outPath = `/tmp/menu_thumbnail_${subject.name}_test3.${ext}`;
  writeFileSync(outPath, Buffer.from(result.base64, "base64"));
  console.log(`[test3] OK (${subject.name}) in ${ms}ms — wrote ${outPath} (mime=${result.mime})`);
}

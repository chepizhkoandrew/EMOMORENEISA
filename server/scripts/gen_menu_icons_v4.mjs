// Generates 1 new menu-card icon (same transparent-icon pipeline as
// gen_menu_icons_v2.mjs/v3.mjs — same style anchor text, kept in sync so new
// icons match the existing set) for the new "Learn by the Book" home card
// (Вчись по підручнику): an open book with a rising staircase/path of steps
// coming out of its pages, conveying structured, step-by-step progress
// through a fixed curriculum.
//
// Icons must stay SQUARE (1:1) — generateIllustration()'s default aspect
// ratio is now 3:4 portrait (tuned for memorization illustrations), so this
// explicitly overrides it back to 1:1 for icon assets.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/gen_menu_icons_v4.mjs

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
    name: "learn_book",
    text: "An open book lying flat, with a small winding staircase of " +
      "glowing steps rising up and forward out of its open pages like a " +
      "path leading upward, one or two small stars/sparkle accents along " +
      "the steps, conveying structured, step-by-step progress through a " +
      "fixed course of lessons in a textbook."
  }
];

const cfg = config.vertexImage;
console.log("[gen] vertexImage config:", {
  enabled: cfg.enabled,
  projectId: cfg.projectId || "(none)",
  location: cfg.location,
  model: cfg.model
});

if (!cfg.enabled || !cfg.projectId) {
  console.error("[gen] FAIL: Vertex image generation is disabled.");
  process.exit(2);
}

for (const subject of subjects) {
  const prompt = `${TRANSPARENT_ICON_STYLE}\n\nSubject: ${subject.text}`;
  const t0 = Date.now();
  const result = await generateIllustration(prompt, "1:1");
  const ms = Date.now() - t0;

  if (!result?.base64) {
    console.error(`[gen] FAIL (${subject.name}): no illustration returned after ${ms}ms.`);
    continue;
  }

  const ext = (result.mime || "image/png").includes("png") ? "png" : "jpg";
  const outPath = `/tmp/menu_icon_${subject.name}_raw.${ext}`;
  writeFileSync(outPath, Buffer.from(result.base64, "base64"));
  console.log(`[gen] OK (${subject.name}) in ${ms}ms — wrote ${outPath}`);
}

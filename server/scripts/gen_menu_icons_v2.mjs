// Regenerates 3 menu-card icons (same transparent-icon pipeline as
// gen_menu_icons.mjs — same style anchor text, kept in sync so new icons
// match the existing set): the calendar icon becomes a parrot+repeat-cycle
// for the "Your Words Calendar" -> "Remember with Repetition" rename, the
// "Your topic" brain icon becomes a plain question mark, and the "Learn from
// what you see" eye becomes an eye-as-camera-lens.
//
// Icons must stay SQUARE (1:1) — generateIllustration()'s default aspect
// ratio is now 3:4 portrait (tuned for memorization illustrations), so this
// explicitly overrides it back to 1:1 for icon assets.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/gen_menu_icons_v2.mjs

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
    name: "words_calendar",
    text: "A colorful parrot perched beside a circular recurring/refresh " +
      "arrow cycle, small sparkle accents, conveying spaced repetition " +
      "and repeated practice."
  },
  {
    name: "parrot_brain",
    text: "One large bold question mark standing alone with small sparkle " +
      "stars and a subtle swirl accent around it — no speech bubble, no " +
      "other objects — conveying an open, user-chosen topic to ask about."
  },
  {
    name: "eye_see",
    text: "A camera where the lens is a stylized wide-open eye, small " +
      "sparkle accents, conveying seeing and photographing the world to " +
      "learn from it."
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

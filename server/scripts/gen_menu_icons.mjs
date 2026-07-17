// Batch-generates the 8 remaining menu-card icons using the transparent-icon
// pipeline validated in test_menu_thumbnail3.mjs: generate on a near-white
// background (the model can't output real alpha), write raw PNGs to /tmp for
// knockout_bg.py to post-process into true transparent icons.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/gen_menu_icons.mjs

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
    name: "speaking",
    text: "Two colorful overlapping speech bubbles, one with a small " +
      "sound-wave squiggle inside it, conveying an animated spoken " +
      "conversation."
  },
  {
    name: "memory",
    text: "A glowing golden brain with small sparkle stars and a few " +
      "floating star glints around it, conveying memory and recall."
  },
  {
    name: "grammar",
    text: "An open book with glowing golden pages and a quill pen resting " +
      "on it, with small sparkle accents, conveying grammar and language " +
      "rules."
  },
  {
    name: "words_calendar",
    text: "A calendar page with one date highlighted by a glowing star, " +
      "small rounded word-tag shapes floating around it, conveying a " +
      "daily queue of words to review."
  },
  {
    name: "remember_music",
    text: "A musical eighth note with a small sparkle trail and a couple " +
      "of sound-wave ripple arcs around it, conveying learning through " +
      "music."
  },
  {
    name: "explain_rules",
    text: "An open book with a glowing lightbulb rising just above it, " +
      "small sparkle accents, conveying learning and explaining rules."
  },
  {
    name: "verbs_times",
    text: "A stylized clock or stopwatch face with a small swirling " +
      "motion-arrow curling around it, conveying verb tenses and timing."
  },
  {
    name: "free_forum",
    text: "A speech bubble with a large bold question mark inside it and " +
      "a small camera icon beside it, conveying free-form questions with " +
      "photo attachments."
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
  const result = await generateIllustration(prompt);
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

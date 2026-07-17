// Retry for the 3 subjects that hit Vertex's rate limit in gen_menu_icons.mjs,
// with a delay between each call this time.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/gen_menu_icons_retry.mjs

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

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const cfg = config.vertexImage;
if (!cfg.enabled || !cfg.projectId) {
  console.error("[retry] FAIL: Vertex image generation is disabled.");
  process.exit(2);
}

for (const subject of subjects) {
  const prompt = `${TRANSPARENT_ICON_STYLE}\n\nSubject: ${subject.text}`;
  let attempt = 0;
  let result = null;
  while (attempt < 3 && !result?.base64) {
    if (attempt > 0) {
      const waitMs = 15000 * attempt;
      console.log(`[retry] (${subject.name}) attempt ${attempt + 1}, waiting ${waitMs}ms...`);
      await sleep(waitMs);
    }
    const t0 = Date.now();
    result = await generateIllustration(prompt);
    const ms = Date.now() - t0;
    if (result?.base64) {
      const ext = (result.mime || "image/png").includes("png") ? "png" : "jpg";
      const outPath = `/tmp/menu_icon_${subject.name}_raw.${ext}`;
      writeFileSync(outPath, Buffer.from(result.base64, "base64"));
      console.log(`[retry] OK (${subject.name}) in ${ms}ms — wrote ${outPath}`);
    } else {
      console.error(`[retry] FAIL (${subject.name}) attempt ${attempt + 1} after ${ms}ms.`);
    }
    attempt++;
  }
  await sleep(8000); // pace requests to avoid re-triggering the rate limit
}

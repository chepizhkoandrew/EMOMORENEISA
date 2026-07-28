// Regenerates 3 menu-card icons (same transparent-icon pipeline as
// gen_menu_icons_v2.mjs — same style anchor text, kept in sync so new icons
// match the existing set): "Learn from what you see" becomes a hand holding
// a phone photographing a stylized eye, "Role Play" keeps its theater masks
// but adds studio podcast microphones, and "Remember with Music" becomes a
// karaoke microphone in front of a lyrics screen.
//
// Icons must stay SQUARE (1:1) — generateIllustration()'s default aspect
// ratio is now 3:4 portrait (tuned for memorization illustrations), so this
// explicitly overrides it back to 1:1 for icon assets.
//
// Usage (from server/, with the Railway-sourced credentials):
//   railway run --service api node scripts/gen_menu_icons_v3.mjs

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
    name: "eye_see",
    text: "A hand holding up a smartphone taking a photo, and the phone's " +
      "screen shows a stylized wide-open eye instead of a normal photo, " +
      "small sparkle accents around it, conveying learning by pointing " +
      "your camera at the world around you."
  },
  {
    name: "role_play",
    text: "A pair of classic theater masks (one smiling, one with a " +
      "different playful expression) slightly overlapping, together with " +
      "a studio podcast microphone on a small stand right beside them, " +
      "small sparkle accents, conveying role-play performed like a podcast " +
      "show."
  },
  {
    name: "remember_music",
    text: "A karaoke microphone in front of a small rectangular screen " +
      "displaying a few lines of song lyrics, small sparkle accents and a " +
      "musical note or two nearby, conveying learning and remembering " +
      "through singing along."
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

// One-off asset script: generates a single canonical "Madrid the dog" cutout —
// on-model (fed the real reference photo below), drawn in the same flat-vector
// illustration style as every generated scene — then keys its flat backdrop
// color out into a true-alpha PNG so it can be composited onto Roleplay
// scenes at request time (see server/src/composite.js). Not part of any
// runtime request path — run this once (or whenever the mascot pose/asset
// needs regenerating) and commit the resulting PNG to
// server/assets/madrid_cutout.png.
//
// Gemini 2.5 Flash Image doesn't reliably produce real alpha transparency no
// matter how it's asked (same reason gen_menu_icons_v2.mjs's outputs are
// named "_raw" — they need a manual matte pass too) — it just paints a flat
// backdrop color instead, and not always the exact hex requested. So this
// script generates against an explicit chroma-key green, samples the color it
// actually got, and keys that out itself rather than assuming the requested
// hex landed exactly.
//
// Usage (from server/, with the Railway-sourced credentials so Vertex auth is
// available — same pattern as gen_menu_icons_v2.mjs):
//   railway run --service api node scripts/gen_madrid_mascot.mjs

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { config } from "../src/config.js";
import { generateIllustration, ILLUSTRATION_STYLE_ANCHOR } from "../src/providers.js";
import { samplePixelColorHex, keyOutToAlphaPng } from "../src/composite.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REFERENCE_PHOTO_PATH = path.join(
  __dirname,
  "../../EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Onboarding/Assets/dog/professor_madrid_01.png"
);
const OUT_DIR = path.join(__dirname, "../assets");
const RAW_OUT_PATH = path.join(OUT_DIR, "madrid_cutout_raw.png");
const FINAL_OUT_PATH = path.join(OUT_DIR, "madrid_cutout.png");

const PROMPT = `${ILLUSTRATION_STYLE_ANCHOR}

Subject: the exact dog shown in the attached reference photo — same fur
color, markings, and face — redrawn in this illustration's flat-vector
style, in a warm, welcoming "podcast host" pose: standing on his hind legs,
holding a small microphone in one paw, the other paw gesturing outward as
if introducing a guest. Friendly, theatrical, a little professorial. Full
body visible, some clear space around him.

The background MUST be a single, perfectly flat, solid chroma-key green
(#00FF00, pure saturated green, no gradient, no texture, no shadow, no
ground plane, no scene of any kind) filling every pixel not covered by the
dog himself — this exact green will be keyed out programmatically after
generation, so it must not appear anywhere on the dog's own fur, clothing,
or the microphone. Absolutely no text, letters, numbers, or words anywhere
in the image.`;

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

const referenceBuf = readFileSync(REFERENCE_PHOTO_PATH);
const imageParts = [
  { inlineData: { mimeType: "image/png", data: referenceBuf.toString("base64") } }
];

console.log(`[gen] using reference photo: ${REFERENCE_PHOTO_PATH} (${referenceBuf.length} bytes)`);

const t0 = Date.now();
const result = await generateIllustration(PROMPT, "3:4", imageParts);
const ms = Date.now() - t0;

if (!result?.base64) {
  console.error(`[gen] FAIL: no illustration returned after ${ms}ms.`);
  process.exit(1);
}

mkdirSync(OUT_DIR, { recursive: true });
const rawBuffer = Buffer.from(result.base64, "base64");
writeFileSync(RAW_OUT_PATH, rawBuffer);
console.log(`[gen] OK in ${ms}ms — wrote raw ${RAW_OUT_PATH} (mime: ${result.mime})`);

const keyColor = await samplePixelColorHex(rawBuffer, 2, 2);
console.log(`[gen] sampled backdrop color at (2,2): ${keyColor}`);

const alphaPng = await keyOutToAlphaPng(rawBuffer, keyColor);
writeFileSync(FINAL_OUT_PATH, alphaPng);
console.log(`[gen] keyed out backdrop — wrote ${FINAL_OUT_PATH}`);
console.log(
  "[gen] Inspect the PNG (Preview.app should show a checkerboard, not a solid " +
  "color) for true alpha transparency, clean edges, and on-model likeness " +
  "before committing. Tune similarity/blend in keyOutToAlphaPng() if fur " +
  "edges look fringed or too much of the dog got keyed out."
);

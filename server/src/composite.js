import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import ffmpegPath from "ffmpeg-static";
import { config } from "./config.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MASCOT_PATH = path.join(__dirname, "../assets/madrid_cutout.png");

function runFfmpeg(args, inputBuffer) {
  return new Promise((resolve, reject) => {
    if (!ffmpegPath) return reject(new Error("ffmpeg-static unavailable"));
    const ff = spawn(ffmpegPath, args);
    const out = [];
    ff.stdout.on("data", (d) => out.push(d));
    ff.on("error", reject);
    ff.on("close", (code) => {
      if (code === 0 && out.length) return resolve(Buffer.concat(out));
      reject(new Error(`ffmpeg exited ${code}`));
    });
    ff.stdin.on("error", () => {});
    ff.stdin.write(inputBuffer);
    ff.stdin.end();
  });
}

// One-off tuning helper: reads back the RGB of a single pixel via an ffmpeg
// crop, so the mascot-generation script can sample the actual backdrop color
// it got (the model doesn't reliably hit the exact hex it's asked for) instead
// of a hand-guessed constant. Returns a "0xRRGGBB" string for colorkey.
export async function samplePixelColorHex(buffer, x, y) {
  const args = [
    "-hide_banner", "-loglevel", "error",
    "-i", "pipe:0",
    "-vf", `crop=1:1:${x}:${y}`,
    "-frames:v", "1",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"
  ];
  const raw = await runFfmpeg(args, buffer);
  const [r, g, b] = [raw[0], raw[1], raw[2]];
  const hex = (n) => n.toString(16).padStart(2, "0");
  return `0x${hex(r)}${hex(g)}${hex(b)}`;
}

// One-off post-processing step, not part of any request path: Gemini 2.5
// Flash Image doesn't actually produce alpha transparency despite being asked
// to (same failure mode noted in gen_menu_icons_v2.mjs's "_raw" output
// naming) — it just paints a flat backdrop color. This keys that flat color
// out and writes a genuine RGBA PNG, so the *asset on disk* is truly
// transparent (openable in Preview.app showing a checkerboard) rather than
// re-running colorkey on every single scene composite at request time. Used
// by scripts/gen_madrid_mascot.mjs right after generation.
// Defaults tuned by hand against the committed madrid_cutout_raw.png: low
// enough to leave the dog's own fur/harness colors untouched, just high
// enough to fully clear the soft drop-shadow ellipse the generator paints
// under his feet (which similarity 0.3 caught, but at the cost of eating most
// of his fur — see git history / plan notes for the comparison sweep).
export async function keyOutToAlphaPng(rawBuffer, keyColor, { similarity = 0.13, blend = 0.02 } = {}) {
  const args = [
    "-hide_banner", "-loglevel", "error",
    "-i", "pipe:0",
    "-vf", `colorkey=${keyColor}:${similarity}:${blend},format=rgba`,
    "-frames:v", "1",
    "-f", "image2pipe", "-vcodec", "png", "pipe:1"
  ];
  return runFfmpeg(args, rawBuffer);
}

// Composites the canonical Madrid mascot cutout (server/assets/
// madrid_cutout.png — a true-alpha PNG, see scripts/gen_madrid_mascot.mjs)
// onto a generated Roleplay scene, bottom-left, scaled relative to the
// scene's own height so the mascot reads consistently across differently-
// shaped scenes. Mirrors image.js's pngToJpeg spawn/pipe pattern. On any
// ffmpeg failure this resolves with the ORIGINAL scene bytes so a compositing
// hiccup never drops the scene image entirely.
export async function compositeMascot(
  sceneBuffer,
  { quality = config.image.jpegQuality, heightFraction = 0.35, margin = 24 } = {}
) {
  if (!ffmpegPath) return sceneBuffer;

  const q = Math.max(2, Math.min(31, Math.round(31 - (quality / 100) * 29)));
  const filter =
    `[1:v][0:v]scale2ref=w=-1:h=main_h*${heightFraction}[mascot][bg];` +
    `[bg][mascot]overlay=x=${margin}:y=main_h-overlay_h-${margin}:format=auto[out]`;

  const args = [
    "-hide_banner", "-loglevel", "error",
    "-i", "pipe:0",
    "-i", MASCOT_PATH,
    "-filter_complex", filter,
    "-map", "[out]",
    "-frames:v", "1",
    "-q:v", String(q),
    "-f", "mjpeg", "pipe:1"
  ];

  try {
    return await runFfmpeg(args, sceneBuffer);
  } catch (_) {
    return sceneBuffer;
  }
}

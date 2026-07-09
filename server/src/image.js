import { spawn } from "node:child_process";
import ffmpegPath from "ffmpeg-static";
import { config } from "./config.js";

// Transcode an arbitrary raster image (PNG/JPEG/WebP from Vertex) into a small
// baseline JPEG: scale the longest side down to `maxSize` (preserving aspect,
// never upscaling) and re-encode at `quality`. This mirrors pcmToAac's role for
// audio — it shrinks the payload so the same illustration is cheap to store in
// Supabase and fast to download to the phone. On any ffmpeg failure it resolves
// with the ORIGINAL bytes so a transcode hiccup never drops the illustration.
export function pngToJpeg(
  inputBuffer,
  { quality = config.image.jpegQuality, maxSize = config.image.maxSize } = {}
) {
  return new Promise((resolve) => {
    if (!ffmpegPath) return resolve(inputBuffer);

    // ffmpeg -q:v is an inverse quality scale (2 = best, 31 = worst). Map a
    // 0-100 quality knob onto ~2..31 so config stays intuitive.
    const q = Math.max(2, Math.min(31, Math.round(31 - (quality / 100) * 29)));
    const scale = `scale='min(${maxSize},iw)':'min(${maxSize},ih)':force_original_aspect_ratio=decrease`;

    const args = [
      "-hide_banner", "-loglevel", "error",
      "-i", "pipe:0",
      "-vf", scale,
      "-frames:v", "1",
      "-q:v", String(q),
      "-f", "mjpeg", "pipe:1"
    ];

    const ff = spawn(ffmpegPath, args);
    const out = [];
    ff.stdout.on("data", (d) => out.push(d));
    ff.on("error", () => resolve(inputBuffer));
    ff.on("close", (code) => {
      if (code === 0 && out.length) return resolve(Buffer.concat(out));
      resolve(inputBuffer);
    });

    ff.stdin.on("error", () => {});
    ff.stdin.write(inputBuffer);
    ff.stdin.end();
  });
}

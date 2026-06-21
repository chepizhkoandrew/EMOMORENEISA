import { spawn } from "node:child_process";
import ffmpegPath from "ffmpeg-static";
import { config } from "./config.js";

// Transcode raw signed-16-bit little-endian PCM (mono, 24kHz from Gemini's
// "audio/L16;rate=24000") into AAC-LC in an ADTS stream. ADTS is chosen over an
// .m4a/MP4 container because each segment is self-contained and streamable, so
// AVAudioPlayer plays it directly with no container seeking. AAC is ~10-15x
// smaller than PCM, which cuts both Supabase storage/egress and the on-device
// download time (the 3.5s first-segment latency the user wants to shave).
export function pcmToAac(
  pcmBuffer,
  { sampleRate = 24000, channels = 1, bitrate = config.audio.aacBitrate } = {}
) {
  return new Promise((resolve, reject) => {
    if (!ffmpegPath) return reject(new Error("ffmpeg_unavailable"));

    const args = [
      "-hide_banner", "-loglevel", "error",
      "-f", "s16le", "-ar", String(sampleRate), "-ac", String(channels), "-i", "pipe:0",
      "-c:a", "aac", "-b:a", bitrate,
      "-f", "adts", "pipe:1"
    ];

    const ff = spawn(ffmpegPath, args);
    const out = [];
    const err = [];

    ff.stdout.on("data", (d) => out.push(d));
    ff.stderr.on("data", (d) => err.push(d));
    ff.on("error", reject);
    ff.on("close", (code) => {
      if (code === 0 && out.length) return resolve(Buffer.concat(out));
      reject(new Error(`ffmpeg_failed_${code}: ${Buffer.concat(err).toString().slice(0, 200)}`));
    });

    // Ignore EPIPE if ffmpeg exits before we finish writing.
    ff.stdin.on("error", () => {});
    ff.stdin.write(pcmBuffer);
    ff.stdin.end();
  });
}

"""ACE-Step song generation, hosted on Modal instead of Cloud Run.

Cloud Run's public routing never reliably dispatched external traffic to our
GPU-attached container in the professor-madrid project (confirmed via
extensive isolation: healthy container, internal health probes reachable,
zero external requests ever logged, across many regions/configs/frameworks).
Modal owns the whole web-serving layer itself (no self-managed HTTP server to
get wrong), so this sidesteps that failure mode entirely.

Deploy:  modal deploy app.py
Test:    curl $(modal app list -> find the healthz URL)/
"""

import base64
import difflib
import os
import re
import subprocess
import tempfile
import time
import unicodedata

import modal
from fastapi import Header, HTTPException

app = modal.App("ace-step-music")

MODEL_DIR = "/models/ace-step"
WHISPER_DIR = "/models/faster-whisper-small"
INFER_STEPS = 60


def _download_model():
    from huggingface_hub import snapshot_download

    snapshot_download("ACE-Step/ACE-Step-v1-3.5B", local_dir=MODEL_DIR)
    # Whisper is used post-generation to time-align the known lyrics to the
    # rendered audio (karaoke line timings).
    snapshot_download("Systran/faster-whisper-small", local_dir=WHISPER_DIR)


gpu_image = (
    modal.Image.from_registry("pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime", add_python="3.11")
    .apt_install("git", "ffmpeg")
    .pip_install(
        "huggingface_hub",
        "diffusers==0.33.1",
        "faster-whisper",
        "git+https://github.com/ace-step/ACE-Step.git",
    )
    .run_function(_download_model)
)

light_image = modal.Image.debian_slim(python_version="3.11").pip_install("fastapi[standard]")

music_key_secret = modal.Secret.from_name("music-service-key")


# --- Lyrics-to-audio alignment (karaoke timings) -------------------------------

def _sung_lines(lyrics: str):
    """Lyric lines that are actually sung: drops blanks and [verse]-style markers."""
    out = []
    for line in lyrics.splitlines():
        line = line.strip()
        if not line or (line.startswith("[") and line.endswith("]")):
            continue
        out.append(line)
    return out


def _norm_tokens(text: str):
    """Accent-folded lowercase word tokens, so sung 'corazón' matches whisper's
    'corazon' (and vice versa) regardless of punctuation."""
    folded = "".join(
        c for c in unicodedata.normalize("NFD", text.lower()) if unicodedata.category(c) != "Mn"
    )
    return re.findall(r"[a-z0-9]+", folded)


def align_lyrics(whisper_model, audio_path: str, lyrics: str, duration: float):
    """Line-level timings for the known lyrics against the rendered audio.

    Whisper transcribes with word timestamps; the word stream is fuzzy-matched
    (SequenceMatcher over accent-folded tokens) back onto the lyric lines we fed
    the music model. Sung vocals transcribe imperfectly, so lines that never
    match are interpolated between their matched neighbours. Returns None when
    too little matches to trust (caller falls back to heuristic timings).
    """
    lines = _sung_lines(lyrics)
    if not lines:
        return None

    # Flatten lyrics into tokens, remembering which line each token belongs to.
    lyric_tokens, token_line = [], []
    for i, line in enumerate(lines):
        for tok in _norm_tokens(line):
            lyric_tokens.append(tok)
            token_line.append(i)
    if not lyric_tokens:
        return None

    segments, _ = whisper_model.transcribe(
        audio_path,
        language="es",
        word_timestamps=True,
        beam_size=5,
        condition_on_previous_text=False,
        vad_filter=True,
    )
    heard = []  # (token, start, end)
    for seg in segments:
        for w in seg.words or []:
            toks = _norm_tokens(w.word)
            for tok in toks:
                heard.append((tok, float(w.start), float(w.end)))
    if not heard:
        return None

    matcher = difflib.SequenceMatcher(
        a=lyric_tokens, b=[h[0] for h in heard], autojunk=False
    )
    token_time = {}  # lyric token index -> (start, end)
    matched = 0
    for block in matcher.get_matching_blocks():
        for k in range(block.size):
            token_time[block.a + k] = (heard[block.b + k][1], heard[block.b + k][2])
            matched += 1
    if matched / len(lyric_tokens) < 0.35:
        return None

    # Per-line span from its matched tokens.
    spans = [None] * len(lines)
    for idx, (s, e) in token_time.items():
        li = token_line[idx]
        if spans[li] is None:
            spans[li] = [s, e]
        else:
            spans[li][0] = min(spans[li][0], s)
            spans[li][1] = max(spans[li][1], e)

    # Interpolate unmatched lines between matched neighbours, weighted by length.
    def fill_gap(lo_i, hi_i, lo_t, hi_t):
        gap = list(range(lo_i + 1, hi_i))
        weights = [max(1, len(lines[g])) for g in gap]
        total = sum(weights)
        t = lo_t
        for g, w in zip(gap, weights):
            step = (hi_t - lo_t) * (w / total)
            spans[g] = [t, t + step]
            t += step

    matched_idx = [i for i, s in enumerate(spans) if s is not None]
    first, last = matched_idx[0], matched_idx[-1]
    if first > 0:
        fill_gap(-1, first, max(0.0, spans[first][0] - 2.0 * first), spans[first][0])
    if last < len(lines) - 1:
        fill_gap(last, len(lines), spans[last][1], min(duration, spans[last][1] + 2.0 * (len(lines) - 1 - last)))
    for i in range(len(matched_idx) - 1):
        a, b = matched_idx[i], matched_idx[i + 1]
        if b - a > 1:
            fill_gap(a, b, spans[a][1], spans[b][0])

    # Enforce monotonic, clamped spans.
    prev_end = 0.0
    out = []
    for i, line in enumerate(lines):
        s, e = spans[i]
        s = max(prev_end, min(s, duration))
        e = max(s + 0.2, min(e, duration))
        prev_end = e
        out.append({"text": line, "startSec": round(s, 2), "endSec": round(e, 2)})
    return out


@app.cls(gpu="T4", image=gpu_image, scaledown_window=300, timeout=600)
class ACEStepService:
    @modal.enter()
    def load(self):
        from acestep.pipeline_ace_step import ACEStepPipeline

        self.pipeline = ACEStepPipeline(checkpoint_dir=MODEL_DIR, dtype="bfloat16", torch_compile=False)
        self.whisper = None

    def _whisper(self):
        # Lazy: only songs pay the ~1GB load, and only once per container.
        if self.whisper is None:
            from faster_whisper import WhisperModel

            try:
                self.whisper = WhisperModel(WHISPER_DIR, device="cuda", compute_type="float16")
            except Exception:
                # VRAM contention with ACE-Step or missing CUDA support: CPU is
                # slower (~10-20s for a 60s song) but always works.
                self.whisper = WhisperModel(WHISPER_DIR, device="cpu", compute_type="int8")
        return self.whisper

    @modal.method()
    def generate(self, prompt: str, lyrics: str, duration_sec: int = 30):
        duration = max(10, min(int(duration_sec), 150))
        started = time.time()

        with tempfile.TemporaryDirectory() as tmp:
            wav_path = os.path.join(tmp, "song.wav")
            # NOTE: keyword names track ACE-Step v1 (pipeline __call__). If you
            # upgrade the acestep package, re-check this signature against
            # https://github.com/ace-step/ACE-Step infer.py defaults.
            self.pipeline(
                audio_duration=float(duration),
                prompt=prompt,
                lyrics=lyrics,
                infer_step=INFER_STEPS,
                guidance_scale=15.0,
                scheduler_type="euler",
                cfg_type="apg",
                omega_scale=10.0,
                guidance_interval=0.5,
                guidance_interval_decay=0.0,
                min_guidance_scale=3.0,
                use_erg_tag=True,
                use_erg_lyric=True,
                use_erg_diffusion=True,
                guidance_scale_text=0.0,
                guidance_scale_lyric=0.0,
                save_path=wav_path,
            )

            mp3_path = os.path.join(tmp, "song.mp3")
            subprocess.run(
                ["ffmpeg", "-y", "-i", wav_path, "-codec:a", "libmp3lame", "-b:a", "128k", mp3_path],
                check=True,
                capture_output=True,
            )
            with open(mp3_path, "rb") as f:
                audio_b64 = base64.b64encode(f.read()).decode("ascii")

            # Karaoke line timings; best-effort — a song without timings still
            # plays, the proxy just falls back to heuristic spacing.
            try:
                lines = align_lyrics(self._whisper(), wav_path, lyrics, float(duration))
            except Exception:
                lines = None

        return {
            "audioBase64": audio_b64,
            "mime": "audio/mpeg",
            "durationSec": duration,
            "lines": lines or [],
            "generationSeconds": round(time.time() - started, 1),
        }


@app.function(image=light_image, secrets=[music_key_secret])
@modal.fastapi_endpoint(method="POST")
def generate(item: dict, x_api_key: str = Header(None)):
    expected = os.environ.get("MUSIC_SERVICE_KEY", "")
    if expected and x_api_key != expected:
        raise HTTPException(status_code=401, detail="bad_api_key")

    prompt = (item.get("prompt") or "").strip()
    lyrics = (item.get("lyrics") or "").strip()
    if not prompt or not lyrics:
        raise HTTPException(status_code=400, detail="missing_prompt_or_lyrics")

    result = ACEStepService().generate.remote(prompt, lyrics, item.get("duration_sec", 30))
    return result


@app.function(image=light_image)
@modal.fastapi_endpoint(method="GET")
def healthz():
    return {"ok": True, "service": "ace-step-music-modal"}

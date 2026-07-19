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
    """Line- and word-level timings for the known lyrics against the rendered audio.

    Whisper transcribes with word timestamps; the word stream is fuzzy-matched
    (SequenceMatcher over accent-folded tokens) back onto the lyric lines we fed
    the music model. Sung vocals transcribe imperfectly, so lines/words that
    never match are interpolated between their matched neighbours. Returns None
    when too little matches to trust (caller falls back to heuristic timings).
    """
    lines = _sung_lines(lyrics)
    if not lines:
        return None

    # Flatten lyrics into (display_word, norm_token) pairs, remembering which
    # line each word belongs to. A display word can fold into >1 norm token
    # (rare, e.g. hyphenated) or 0 (pure punctuation) — token_word maps each
    # norm token back to its owning display-word index within the line so
    # per-word spans can be assembled the same way per-line spans are.
    lyric_tokens, token_line, token_word = [], [], []
    line_words = []  # line_words[i] = display words (original casing/accents) for line i
    for i, line in enumerate(lines):
        words = line.split()
        line_words.append(words)
        for wi, word in enumerate(words):
            for tok in _norm_tokens(word):
                lyric_tokens.append(tok)
                token_line.append(i)
                token_word.append(wi)
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
    ratio = matched / len(lyric_tokens)
    print(f"[align] match ratio {ratio:.2f} ({matched}/{len(lyric_tokens)} tokens, {len(heard)} heard)")
    if ratio < 0.35:
        return None

    # Per-word spans (matched tokens), grouped by (line, word) — used to
    # synthesize word-level timings below, once line spans are finalized.
    word_time = {}  # (line_idx, word_idx) -> [start, end]
    for idx, (s, e) in token_time.items():
        key = (token_line[idx], token_word[idx])
        if key not in word_time:
            word_time[key] = [s, e]
        else:
            word_time[key][0] = min(word_time[key][0], s)
            word_time[key][1] = max(word_time[key][1], e)

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

    # Word-level timings within each line: matched words keep their real
    # Whisper span; unmatched words are interpolated between matched
    # neighbours (same length-weighted technique as fill_gap above), bounded
    # by the line's own final [startSec, endSec] so words never spill past
    # their line even when the line itself was interpolated.
    def line_word_spans(li, line_start, line_end):
        words = line_words[li]
        if not words:
            return []
        wspans = [word_time.get((li, wi)) for wi in range(len(words))]
        matched_wi = [wi for wi, s in enumerate(wspans) if s is not None]

        def fill_word_gap(lo_wi, hi_wi, lo_t, hi_t):
            gap = list(range(lo_wi + 1, hi_wi))
            weights = [max(1, len(words[g])) for g in gap]
            total = sum(weights)
            t = lo_t
            for g, w in zip(gap, weights):
                step = (hi_t - lo_t) * (w / total)
                wspans[g] = [t, t + step]
                t += step

        if not matched_wi:
            # No word in this line matched — spread evenly by length across
            # the line's own (possibly interpolated) span.
            fill_word_gap(-1, len(words), line_start, line_end)
        else:
            first_wi, last_wi = matched_wi[0], matched_wi[-1]
            if first_wi > 0:
                fill_word_gap(-1, first_wi, line_start, wspans[first_wi][0])
            if last_wi < len(words) - 1:
                fill_word_gap(last_wi, len(words), wspans[last_wi][1], line_end)
            for i in range(len(matched_wi) - 1):
                a, b = matched_wi[i], matched_wi[i + 1]
                if b - a > 1:
                    fill_word_gap(a, b, wspans[a][1], wspans[b][0])

        # Clamp + enforce monotonic within [line_start, line_end]. Unlike the
        # line-level pass above (which can let a final line's endSec run past
        # `duration` by its minimum-span floor), words must never spill past
        # their own line — the highlight sweep treats line_end as a hard
        # boundary — so the minimum span is applied *inside* the clamp, not
        # after it.
        prev_end = line_start
        result = []
        for wi, word in enumerate(words):
            s, e = wspans[wi] if wspans[wi] else (prev_end, prev_end + 0.1)
            s = max(prev_end, min(s, line_end))
            e = min(line_end, max(s + 0.05, min(e, line_end)))
            prev_end = e
            result.append({"text": word, "startSec": round(s, 2), "endSec": round(e, 2)})
        return result

    for i, entry in enumerate(out):
        entry["words"] = line_word_spans(i, entry["startSec"], entry["endSec"])

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
            # plays, the proxy just falls back to heuristic spacing. Logged
            # (was previously silent on both failure paths) so a bad-sync
            # report can actually be diagnosed instead of guessed at.
            try:
                lines = align_lyrics(self._whisper(), wav_path, lyrics, float(duration))
                if lines is None:
                    print("[align] rejected: match ratio below threshold or no lyric tokens")
                else:
                    print(f"[align] ok: {len(lines)} lines aligned")
            except Exception:
                import traceback
                print("[align] EXCEPTION:")
                traceback.print_exc()
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

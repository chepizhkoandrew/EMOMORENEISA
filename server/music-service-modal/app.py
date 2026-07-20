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
import json
import os
import re
import subprocess
import tempfile
import time
import unicodedata
import urllib.parse
import urllib.request

import modal
from fastapi import Header, HTTPException

app = modal.App("ace-step-music")

# Instant rollback switch: if ACE-Step 1.5's Spanish output or latency
# disappoints in practice, flip this to False and redeploy — no other code
# change needed, the old v1 pipeline path is kept intact below.
USE_ACESTEP_15 = False

MODEL_DIR = "/models/ace-step"
# "small" was too weak on chanted/shouted vocals over dense backing music
# (2026-07-19 "gol gol españa" incident — match ratio 0.49, garbled
# transcription of the whole chorus). "medium" is the largest step up that
# still leaves safe VRAM headroom on a T4 alongside ACE-Step (~7.4-7.8GB
# resident, confirmed via Modal logs) and Demucs; large-v3 (~6GB) would run
# the three too close to the 16GB ceiling.
WHISPER_DIR = "/models/faster-whisper-medium"
DEMUCS_MODEL = "htdemucs"
INFER_STEPS = 60


def _download_model():
    from huggingface_hub import snapshot_download

    snapshot_download("ACE-Step/ACE-Step-v1-3.5B", local_dir=MODEL_DIR)
    # Whisper is used post-generation to time-align the known lyrics to the
    # rendered audio (karaoke line timings).
    snapshot_download("Systran/faster-whisper-medium", local_dir=WHISPER_DIR)
    # Demucs (vocal isolation, run before transcription) downloads its own
    # pretrained checkpoint on first use — pre-warm it into the image here so
    # the first real request doesn't pay a cold download.
    from demucs.pretrained import get_model

    get_model(DEMUCS_MODEL)


gpu_image = (
    modal.Image.from_registry("pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime", add_python="3.11")
    .apt_install("git", "ffmpeg")
    .pip_install(
        "huggingface_hub",
        "diffusers==0.33.1",
        "faster-whisper",
        "demucs",
        "git+https://github.com/ace-step/ACE-Step.git",
    )
    .run_function(_download_model)
)

light_image = modal.Image.debian_slim(python_version="3.11").pip_install("fastapi[standard]")

music_key_secret = modal.Secret.from_name("music-service-key")


# --- ACE-Step 1.5 (song generation) --------------------------------------------
#
# Runs as a SEPARATE container/GPU from ACEStepService below, deliberately —
# ACE-Step 1.5's own GPU_COMPATIBILITY.md documents a T4's 16GB as fitting the
# XL DiT + 1.7B LM tier only when the whole GPU is available to it alone; our
# alignment pipeline (Whisper-medium + Demucs, ~3.3GB) sharing that same
# budget would risk VRAM contention against a model already using CPU
# offload. Two containers, two independent scale-to-zero lifecycles, no
# contention — ACEStepService.generate() below calls this one via .remote()
# for the audio, then runs vocal isolation + alignment on the result exactly
# as it always has.
#
# Deliberately NOT overriding to the "sft" quality tier here anymore: a
# first attempt setting ACESTEP_CONFIG_PATH=acestep-v15-sft / LM=0.6B still
# downloaded turbo+1.7B regardless (root cause unconfirmed — ruled out
# .env-file precedence, since api_server.py's load_dotenv() call uses
# override=False and no .env file exists in this image anyway). There's also
# an open upstream issue (ace-step/ACE-Step-1.5#200) specifically about SFT
# service-mode initialization being buggy. Using their own `.env.example`
# default pairing (turbo DiT + 1.7B LM — their own "standard configuration")
# sidesteps both the unconfirmed-override mystery and a known-buggy code
# path, at the cost of the faster/distilled tier instead of the full-CFG one
# originally planned. Revisit once there's time to root-cause the override
# behavior properly.
ACESTEP15_DIT_MODEL = "acestep-v15-turbo"
ACESTEP15_LM_MODEL = "acestep-5Hz-lm-1.7B"
ACESTEP15_API_PORT = 8001
ACESTEP15_UV = "/root/.local/bin/uv"
ACESTEP15_DIR = "/opt/acestep15"

acestep15_image = (
    modal.Image.from_registry("pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime", add_python="3.11")
    # build-essential: Triton (vLLM's kernel JIT) needs a C compiler at
    # runtime — its absence surfaced as "Failed to find C compiler" during
    # the first real test, silently falling back to a slower PyTorch path
    # rather than failing outright, but worth fixing properly.
    .apt_install("git", "ffmpeg", "curl", "espeak-ng", "build-essential")
    .run_commands(
        "curl -LsSf https://astral.sh/uv/install.sh | sh",
        f"git clone https://github.com/ace-step/ACE-Step-1.5.git {ACESTEP15_DIR}",
        f"cd {ACESTEP15_DIR} && {ACESTEP15_UV} sync",
    )
    # Modal loads the WHOLE app.py module (including the top-level
    # `from fastapi import ...` used by the webhook function) in every
    # container regardless of which class/function it's actually running —
    # this needs to be importable here even though AceStep15Service itself
    # never touches fastapi (the acestep-api subprocess runs in its own
    # separate uv-managed venv under ACESTEP15_DIR, unaffected either way).
    .pip_install("fastapi[standard]")
)
# NOTE: checkpoints are NOT pre-warmed into the image at build time — their
# own docs state the server auto-downloads weights on first run (resolved
# via ACESTEP_CONFIG_PATH/ACESTEP_LM_MODEL_PATH through their own internal
# registry). First real request after a cold container start pays a
# one-time download cost — observed to be several GB (turbo DiT + 1.7B LM +
# a Qwen embedding model, downloaded in parallel) — well past the original
# 300s health-check budget, which is very likely what actually caused the
# first two 500s (not the model-selection question above). Bumped to 20
# minutes; a warm container (same scaledown_window=300 lifetime) skips this
# entirely on subsequent requests.
ACESTEP15_ENTER_TIMEOUT_S = 1200


@app.cls(gpu="L4", image=acestep15_image, scaledown_window=300, timeout=1800)
class AceStep15Service:
    @modal.enter()
    def load(self):
        env = os.environ.copy()
        env["ACESTEP_CONFIG_PATH"] = ACESTEP15_DIT_MODEL
        env["ACESTEP_LM_MODEL_PATH"] = ACESTEP15_LM_MODEL
        env["ACESTEP_API_PORT"] = str(ACESTEP15_API_PORT)
        env["ACESTEP_API_HOST"] = "127.0.0.1"
        print(f"[acestep15] spawning acestep-api: DIT={env['ACESTEP_CONFIG_PATH']} LM={env['ACESTEP_LM_MODEL_PATH']}")
        self.proc = subprocess.Popen(
            [ACESTEP15_UV, "run", "acestep-api"],
            cwd=ACESTEP15_DIR,
            env=env,
        )
        # DiT + LM cold-load (incl. first-run download) can take a while;
        # poll /health rather than assuming a fixed warm-up time. Logs
        # progress periodically so a slow cold start is visible, not silent.
        deadline = time.time() + ACESTEP15_ENTER_TIMEOUT_S
        healthy = False
        last_log = 0.0
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"[acestep15] acestep-api process exited early with code {self.proc.returncode}")
            if time.time() - last_log > 30:
                print(f"[acestep15] waiting for /health ({int(deadline - time.time())}s left)...")
                last_log = time.time()
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{ACESTEP15_API_PORT}/health", timeout=3) as resp:
                    if resp.status == 200:
                        healthy = True
                        break
            except Exception:
                pass
            time.sleep(2)
        if not healthy:
            raise RuntimeError(f"acestep-api did not become healthy within {ACESTEP15_ENTER_TIMEOUT_S}s")
        print("[acestep15] acestep-api healthy")

    def _post(self, path: str, body: dict, timeout: int = 30) -> dict:
        req = urllib.request.Request(
            f"http://127.0.0.1:{ACESTEP15_API_PORT}{path}",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())

    @modal.method()
    def generate_song(self, prompt: str, lyrics: str, duration_sec: int) -> bytes:
        # /health passing only confirms the web server is up, not that the
        # model is actually loaded into GPU memory — the 2026-07-20 L4 test
        # got past /health then hit a client-side socket TimeoutError on
        # THIS call, most likely because the DiT model lazy-loads on the
        # first real task submission (including its flash_attention_2 ->
        # sdpa -> eager fallback attempts, per their init_service_loader.py
        # source), which can genuinely take several minutes the first time —
        # not a hang, just slower than the original 60s budget assumed.
        submitted = self._post("/release_task", {
            "prompt": prompt,
            "lyrics": lyrics,
            "audio_duration": float(duration_sec),
            "vocal_language": "es",
            # turbo is the distilled, no-CFG tier — 8 steps is their own
            # documented setting for it, not the 50-step CFG figure that
            # applies to sft/base.
            "inference_steps": 8,
        }, timeout=600)
        task_id = submitted["data"]["task_id"]
        print(f"[acestep15] task {task_id} submitted")

        poll_seconds = 1500
        deadline = time.time() + poll_seconds
        result = None
        last_log = 0.0
        while time.time() < deadline:
            if time.time() - last_log > 30:
                print(f"[acestep15] task {task_id} polling... ({int(deadline - time.time())}s left)")
                last_log = time.time()
            polled = self._post("/query_result", {"task_id_list": [task_id]})
            item = polled["data"]
            item = item[0] if isinstance(item, list) else item
            status = item.get("status")
            if status == "succeeded":
                result = item
                break
            if status == "failed":
                raise RuntimeError(f"[acestep15] task {task_id} failed: {item}")
            time.sleep(2)
        if result is None:
            raise RuntimeError(f"[acestep15] task {task_id} timed out after {poll_seconds}s")
        print(f"[acestep15] task {task_id} succeeded")

        audio_path = result.get("file")
        if not audio_path:
            raise RuntimeError(f"[acestep15] task {task_id} succeeded but no file path in result: {result}")
        url = f"http://127.0.0.1:{ACESTEP15_API_PORT}/v1/audio?path={urllib.parse.quote(audio_path, safe='')}"
        with urllib.request.urlopen(url, timeout=60) as resp:
            return resp.read()


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
        print("[align] whisper heard nothing (no words in any segment)")
        return None

    # What Whisper actually transcribed vs. what the lyrics say, side by
    # side — the fastest way to tell "bad audio/transcription" apart from
    # "bad matching logic" when a sync report comes in.
    print(f"[align] expected ({len(lyric_tokens)}): {' '.join(lyric_tokens)}")
    print(f"[align] heard    ({len(heard)}): {' '.join(h[0] for h in heard)}")

    matcher = difflib.SequenceMatcher(
        a=lyric_tokens, b=[h[0] for h in heard], autojunk=False
    )
    token_time = {}  # lyric token index -> (start, end)
    matched = 0
    skipped_short = 0
    for block in matcher.get_matching_blocks():
        if block.size == 0:
            continue
        # A single isolated matched token is unreliable for short/common
        # Spanish function words ("a", "va", "uno", "sin"...) — a garbled
        # transcription can spuriously line one of these up almost anywhere,
        # which is exactly how the 2026-07-19 incident's lines 4-5 got
        # mislabeled "real" despite resting on a near-nonsense heard string.
        # Runs of 2+ consecutive matched tokens are trusted regardless of
        # length since phrase-level correspondence is far less likely to be
        # coincidental.
        if block.size == 1 and len(lyric_tokens[block.a]) < 5:
            skipped_short += 1
            continue
        for k in range(block.size):
            token_time[block.a + k] = (heard[block.b + k][1], heard[block.b + k][2])
            matched += 1
    if skipped_short:
        print(f"[align] distrusted {skipped_short} isolated short-token match(es)")
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
    interpolated_idx = [i for i in range(len(lines)) if i not in matched_idx]
    if interpolated_idx:
        print(f"[align] lines with ZERO matched tokens (fully guessed, not real audio): {interpolated_idx}")
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

    for i, entry in enumerate(out):
        tag = "guessed" if i in interpolated_idx else "real"
        word_summary = " | ".join(f"{w['text']}@{w['startSec']}" for w in entry["words"])
        print(f"[align] line {i} [{tag}] {entry['startSec']}-{entry['endSec']}: \"{entry['text']}\" words: {word_summary}")

    return out


@app.cls(gpu="T4", image=gpu_image, scaledown_window=300, timeout=1800)
class ACEStepService:
    @modal.enter()
    def load(self):
        self.pipeline = None
        if not USE_ACESTEP_15:
            from acestep.pipeline_ace_step import ACEStepPipeline

            self.pipeline = ACEStepPipeline(checkpoint_dir=MODEL_DIR, dtype="bfloat16", torch_compile=False)
        self.whisper = None
        self.demucs = None

    def _whisper(self):
        # Lazy: only songs pay the ~3GB load, and only once per container.
        if self.whisper is None:
            from faster_whisper import WhisperModel

            try:
                self.whisper = WhisperModel(WHISPER_DIR, device="cuda", compute_type="float16")
            except Exception:
                # VRAM contention with ACE-Step or missing CUDA support: CPU is
                # slower but always works.
                self.whisper = WhisperModel(WHISPER_DIR, device="cpu", compute_type="int8")
        return self.whisper

    def _demucs(self):
        # Lazy, same pattern as _whisper — loaded once per container, then
        # reused for every subsequent song that container handles.
        if self.demucs is None:
            from demucs.pretrained import get_model

            model = get_model(DEMUCS_MODEL)
            model.eval()
            try:
                import torch

                if torch.cuda.is_available():
                    model = model.cuda()
            except Exception:
                pass  # falls back to whatever device get_model() defaulted to (cpu)
            self.demucs = model
        return self.demucs

    def _isolate_vocals(self, wav_path: str, tmp_dir: str) -> str:
        """Separates vocals from the backing track before transcription —
        Whisper transcribing the full mixed track (vocals + drums/bass/
        synths) is exactly the condition it struggles with most, and was the
        root cause of the 2026-07-19 chanted-chorus sync failure. Best-effort:
        on any failure, returns the original mixed `wav_path` unchanged so
        alignment still runs on the noisier signal rather than the whole
        job failing.
        """
        try:
            import torch
            import torchaudio
            from demucs.apply import apply_model

            model = self._demucs()
            device = next(model.parameters()).device

            wav, sr = torchaudio.load(wav_path)
            if sr != model.samplerate:
                wav = torchaudio.functional.resample(wav, sr, model.samplerate)
            if wav.shape[0] != model.audio_channels:
                # Mono source, stereo-expecting model (or vice versa).
                if wav.shape[0] == 1 and model.audio_channels == 2:
                    wav = wav.repeat(2, 1)
                elif wav.shape[0] > model.audio_channels:
                    wav = wav[: model.audio_channels]

            with torch.no_grad():
                sources = apply_model(model, wav[None].to(device), split=True)[0]
            vocals = sources[model.sources.index("vocals")].cpu()

            vocals_path = os.path.join(tmp_dir, "vocals.wav")
            torchaudio.save(vocals_path, vocals, model.samplerate)
            return vocals_path
        except Exception as e:
            print(f"[align] vocal isolation failed, aligning against mixed audio instead: {e}")
            return wav_path

    @modal.method()
    def generate(self, prompt: str, lyrics: str, duration_sec: int = 30):
        duration = max(10, min(int(duration_sec), 150))
        started = time.time()

        with tempfile.TemporaryDirectory() as tmp:
            wav_path = os.path.join(tmp, "song.wav")
            if USE_ACESTEP_15:
                # Runs in its own container/GPU (AceStep15Service) — see the
                # class docstring-equivalent comment above it for why this
                # isn't embedded here. Its output format isn't guaranteed to
                # be wav, so normalize through ffmpeg regardless of what
                # comes back (ffmpeg identifies container format from
                # content, not the extension on raw_path).
                audio_bytes = AceStep15Service().generate_song.remote(prompt, lyrics, duration)
                raw_path = os.path.join(tmp, "acestep15_raw")
                with open(raw_path, "wb") as f:
                    f.write(audio_bytes)
                subprocess.run(
                    ["ffmpeg", "-y", "-i", raw_path, wav_path],
                    check=True,
                    capture_output=True,
                )
            else:
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
                vocals_path = self._isolate_vocals(wav_path, tmp)
                lines = align_lyrics(self._whisper(), vocals_path, lyrics, float(duration))
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


@app.function(image=light_image, secrets=[music_key_secret], timeout=1800)
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

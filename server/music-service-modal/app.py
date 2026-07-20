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
DEMUCS_MODEL = "htdemucs"
INFER_STEPS = 60


def _download_model():
    from huggingface_hub import snapshot_download

    snapshot_download("ACE-Step/ACE-Step-v1-3.5B", local_dir=MODEL_DIR)
    # Demucs (vocal isolation, run before forced alignment) downloads its own
    # pretrained checkpoint on first use — pre-warm it into the image here so
    # the first real request doesn't pay a cold download.
    from demucs.pretrained import get_model

    get_model(DEMUCS_MODEL)

    # MMS_FA (forced alignment — see align_lyrics below) downloads its own
    # weights via torch.hub on first use; pre-warm the same way.
    from torchaudio.pipelines import MMS_FA

    MMS_FA.get_model()


gpu_image = (
    modal.Image.from_registry("pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime", add_python="3.11")
    .apt_install("git", "ffmpeg")
    .pip_install(
        "huggingface_hub",
        "diffusers==0.33.1",
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


def align_lyrics(aligner_bundle, audio_path: str, lyrics: str, duration: float):
    """Line- and word-level timings for the known lyrics against the rendered
    audio, via forced alignment (torchaudio MMS_FA) rather than transcription.

    We already know the exact lyrics — no need to ask a model to *recognize*
    what was sung, only *when*. Forced alignment finds the best temporal
    placement of the known text against the audio's acoustic features
    directly, sidestepping full ASR transcription error on top of alignment
    error (the root cause of the 2026-07-19 "gol gol españa" chant failure —
    Whisper's transcription came out garbled, dragging the fuzzy-match ratio
    down to 0.49 and leaving several lines fully guessed).

    Every word always gets *a* placement (forced alignment doesn't "fail to
    match" the way fuzzy-matching against a bad transcription can) — the
    per-word `score` the aligner returns is the trust signal instead: a word
    genuinely sung gets a high score, a word forced into silence or the
    wrong audio (skipped line, ad-lib, instrumental gap — a real risk since
    nothing guarantees the model sang exactly what we asked) gets a low one.
    Logged per word rather than gated on a guessed threshold, so an actual
    cutoff can be calibrated from real score distributions, the same way the
    old 0.35 match-ratio threshold was arrived at empirically.
    """
    import torch
    import torchaudio

    lines = _sung_lines(lyrics)
    if not lines:
        return None

    # Flatten lyrics into a single flat word list across the whole song,
    # remembering which line each word belongs to so per-line spans can be
    # reconstructed from the per-word alignment result afterward.
    line_words = []  # line_words[i] = display words (original casing/accents) for line i
    flat_words = []  # flat display words across the whole song, in order
    for i, line in enumerate(lines):
        words = line.split()
        line_words.append(words)
        flat_words.extend(words)
    if not flat_words:
        return None

    # MMS_FA's vocab is accent-folded lowercase — same fold _norm_tokens
    # already does for the old matcher. Falls back to the raw lowered word
    # if folding strips it to nothing (e.g. a stray punctuation-only token),
    # so word count never drifts from flat_words.
    def _fold(word):
        toks = _norm_tokens(word)
        return "".join(toks) if toks else word.lower()

    normalized = [_fold(w) for w in flat_words]

    model = aligner_bundle["model"]
    tokenizer = aligner_bundle["tokenizer"]
    aligner = aligner_bundle["aligner"]
    sample_rate = aligner_bundle["sample_rate"]
    device = next(model.parameters()).device

    waveform, sr = torchaudio.load(audio_path)
    if sr != sample_rate:
        waveform = torchaudio.functional.resample(waveform, sr, sample_rate)
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)

    with torch.inference_mode():
        emission, _ = model(waveform.to(device))
        token_spans = aligner(emission[0], tokenizer(normalized))

    num_frames = emission.size(1)
    samples_per_frame = waveform.shape[1] / num_frames

    def frame_to_sec(frame_idx):
        return (frame_idx * samples_per_frame) / sample_rate

    # Flat per-word spans (one entry per flat_words element, in order).
    words = []
    for spans, word in zip(token_spans, flat_words):
        if not spans:
            # Defensive fallback — every input token should get a span, but
            # a single odd word failing to align must not crash the song.
            prev_end = words[-1]["endSec"] if words else 0.0
            words.append({"text": word, "startSec": prev_end, "endSec": prev_end + 0.1, "score": -999.0})
            continue
        t0 = frame_to_sec(spans[0].start)
        t1 = frame_to_sec(spans[-1].end)
        score = sum(s.score for s in spans) / len(spans)
        words.append({"text": word, "startSec": t0, "endSec": t1, "score": score})

    # Enforce monotonic, duration-clamped boundaries — forced alignment isn't
    # guaranteed strictly increasing across word/line boundaries, and the
    # client's sweep/scene-sync logic assumes it is.
    prev_end = 0.0
    for w in words:
        s = max(prev_end, min(w["startSec"], duration))
        e = max(s + 0.05, min(w["endSec"], duration))
        w["startSec"], w["endSec"] = round(s, 2), round(e, 2)
        prev_end = e

    real_scores = [w["score"] for w in words if w["score"] > -999.0]
    if real_scores:
        print(
            f"[align] forced-alignment word scores: "
            f"min={min(real_scores):.2f} max={max(real_scores):.2f} "
            f"mean={sum(real_scores) / len(real_scores):.2f}"
        )
    lowest = sorted(words, key=lambda w: w["score"])[:8]
    print(f"[align] lowest-confidence words: {[(w['text'], w['startSec'], round(w['score'], 2)) for w in lowest]}")

    # Reconstruct per-line entries from the flat word list.
    out = []
    wi = 0
    for line in lines:
        n = len(line_words[len(out)])
        entries = words[wi: wi + n]
        wi += n
        out.append({
            "text": line,
            "startSec": entries[0]["startSec"],
            "endSec": entries[-1]["endSec"],
            "words": [{"text": w["text"], "startSec": w["startSec"], "endSec": w["endSec"]} for w in entries],
        })

    for i, entry in enumerate(out):
        word_summary = " | ".join(f"{w['text']}@{w['startSec']}" for w in entry["words"])
        print(f"[align] line {i} {entry['startSec']}-{entry['endSec']}: \"{entry['text']}\" words: {word_summary}")

    return out


@app.cls(gpu="T4", image=gpu_image, scaledown_window=300, timeout=1800)
class ACEStepService:
    @modal.enter()
    def load(self):
        self.pipeline = None
        if not USE_ACESTEP_15:
            from acestep.pipeline_ace_step import ACEStepPipeline

            self.pipeline = ACEStepPipeline(checkpoint_dir=MODEL_DIR, dtype="bfloat16", torch_compile=False)
        self.aligner_bundle = None
        self.demucs = None

    def _forced_aligner(self):
        # Lazy, same pattern as _demucs — loaded once per container, then
        # reused for every subsequent song. MMS_FA replaced faster-whisper
        # here (2026-07-20): forced alignment of the KNOWN lyrics against the
        # audio, instead of transcribing and fuzzy-matching a guess — see
        # align_lyrics()'s docstring for why.
        if self.aligner_bundle is None:
            import torch
            from torchaudio.pipelines import MMS_FA

            model = MMS_FA.get_model()
            model.eval()
            try:
                if torch.cuda.is_available():
                    model = model.cuda()
            except Exception:
                pass
            self.aligner_bundle = {
                "model": model,
                "tokenizer": MMS_FA.get_tokenizer(),
                "aligner": MMS_FA.get_aligner(),
                "sample_rate": MMS_FA.sample_rate,
            }
        return self.aligner_bundle

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
                lines = align_lyrics(self._forced_aligner(), vocals_path, lyrics, float(duration))
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

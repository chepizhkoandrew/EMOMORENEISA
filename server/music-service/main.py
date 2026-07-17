"""ACE-Step song generation service.

Runs on Cloud Run with an NVIDIA L4 GPU, min-instances=0: the instance starts
when a request arrives, stays warm ~15 min, then scales back to zero — so the
GPU only bills while songs are actually being generated. The Railway proxy is
the only caller (shared-secret header); this service is never exposed to the
app directly.
"""

import base64
import os
import subprocess
import tempfile
import threading
import time

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

MUSIC_SERVICE_KEY = os.environ.get("MUSIC_SERVICE_KEY", "")
CHECKPOINT_DIR = os.environ.get("ACE_CHECKPOINT_DIR", "/models/ace-step")
# bfloat16 fits ACE-Step v1-3.5B comfortably in the L4's 24 GB.
DTYPE = os.environ.get("ACE_DTYPE", "bfloat16")
INFER_STEPS = int(os.environ.get("ACE_INFER_STEPS", "60"))

app = FastAPI()

_pipeline = None
_pipeline_lock = threading.Lock()


def get_pipeline():
    """Lazy-load the model once per instance. First call after a cold start
    takes 1-2 minutes; Cloud Run's request timeout must cover it."""
    global _pipeline
    with _pipeline_lock:
        if _pipeline is None:
            from acestep.pipeline_ace_step import ACEStepPipeline

            _pipeline = ACEStepPipeline(
                checkpoint_dir=CHECKPOINT_DIR,
                dtype=DTYPE,
                torch_compile=False,
            )
        return _pipeline


class GenerateRequest(BaseModel):
    prompt: str  # comma-separated style tags, e.g. "reggaeton, latin, upbeat, male vocals"
    lyrics: str  # supports [verse]/[chorus]/[bridge]/[outro] markers
    duration_sec: int = 30


@app.get("/healthz")
def healthz():
    return {"ok": True, "service": "ace-step-music", "model_loaded": _pipeline is not None}


@app.post("/generate")
def generate(req: GenerateRequest, request: Request):
    if MUSIC_SERVICE_KEY and request.headers.get("X-API-Key") != MUSIC_SERVICE_KEY:
        raise HTTPException(status_code=401, detail="bad_api_key")
    if not req.prompt.strip() or not req.lyrics.strip():
        raise HTTPException(status_code=400, detail="missing_prompt_or_lyrics")
    duration = max(10, min(int(req.duration_sec), 150))

    started = time.time()
    pipeline = get_pipeline()

    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "song.wav")
        # NOTE: keyword names track ACE-Step v1 (pipeline __call__). If you
        # upgrade the acestep package, re-check this signature against
        # https://github.com/ace-step/ACE-Step infer.py defaults.
        pipeline(
            audio_duration=float(duration),
            prompt=req.prompt,
            lyrics=req.lyrics,
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

    return {
        "audioBase64": audio_b64,
        "mime": "audio/mpeg",
        "durationSec": duration,
        "generationSeconds": round(time.time() - started, 1),
    }

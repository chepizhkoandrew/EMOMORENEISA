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
import os
import subprocess
import tempfile
import time

import modal
from fastapi import Header, HTTPException

app = modal.App("ace-step-music")

MODEL_DIR = "/models/ace-step"
INFER_STEPS = 60


def _download_model():
    from huggingface_hub import snapshot_download

    snapshot_download("ACE-Step/ACE-Step-v1-3.5B", local_dir=MODEL_DIR)


gpu_image = (
    modal.Image.from_registry("pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime", add_python="3.11")
    .apt_install("git", "ffmpeg")
    .pip_install("huggingface_hub", "diffusers==0.33.1", "git+https://github.com/ace-step/ACE-Step.git")
    .run_function(_download_model)
)

light_image = modal.Image.debian_slim(python_version="3.11").pip_install("fastapi[standard]")

music_key_secret = modal.Secret.from_name("music-service-key")


@app.cls(gpu="T4", image=gpu_image, scaledown_window=300, timeout=600)
class ACEStepService:
    @modal.enter()
    def load(self):
        from acestep.pipeline_ace_step import ACEStepPipeline

        self.pipeline = ACEStepPipeline(checkpoint_dir=MODEL_DIR, dtype="bfloat16", torch_compile=False)

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

        return {
            "audioBase64": audio_b64,
            "mime": "audio/mpeg",
            "durationSec": duration,
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

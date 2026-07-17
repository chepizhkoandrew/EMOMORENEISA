# ACE-Step music generation service for Cloud Run GPU (NVIDIA L4).
# Weights are baked into the image at build time so a cold instance never
# re-downloads ~7 GB from Hugging Face — cold start = model load only.
FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime

RUN apt-get update && apt-get install -y --no-install-recommends git ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the model snapshot (no GPU needed for the download).
ENV ACE_CHECKPOINT_DIR=/models/ace-step
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/ACE-Step-v1-3.5B', local_dir='/models/ace-step')"

COPY main.py .

ENV PORT=8080
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT} --workers 1

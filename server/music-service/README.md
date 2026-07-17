# ACE-Step music service

Self-hosted song generation for the "Create a Song" feature. Wraps
[ACE-Step v1-3.5B](https://huggingface.co/ACE-Step/ACE-Step-v1-3.5B)
(Apache-2.0, text2music **with sung lyrics**, supports Spanish) behind a tiny
FastAPI endpoint. The Railway proxy (`/v1/music/generate`) is the only caller.

## Why Cloud Run GPU (the "on/off by time" answer)

`--min-instances 0` means the GPU instance **does not exist** while nobody is
generating. A request spins one up (cold start ≈ 1–2 min to load the model),
it stays warm ~15 min after the last request, then shuts down by itself.
You pay only for the minutes an instance is actually up — no renting a
24/7 machine, no manual switching.

Rough cost (europe-west4, L4 + 8 vCPU + 32 GiB): **≈ $0.90–1.00 per instance-hour**,
billed per second. A warm 60s song generates in well under a minute; even with
cold starts a test session costs cents. Hard monthly ceiling: `--max-instances 1`.

Kill switch (hard off): remove `MUSIC_SERVICE_URL` from Railway (the proxy then
returns `music_not_configured`), or delete the service:
`gcloud run services delete ace-step-music --region europe-west4`.

## Deploy

```bash
cd server/music-service
MUSIC_SERVICE_KEY=$(openssl rand -hex 24) ./deploy.sh   # keep the secret
```

Then on Railway (api service) set:

```
MUSIC_SERVICE_URL=https://ace-step-music-....run.app
MUSIC_SERVICE_KEY=<same secret>
```

## API

`POST /generate` — header `X-API-Key: <secret>`

```json
{ "prompt": "reggaeton, latin, upbeat, male vocals", "lyrics": "[verse]\n...", "duration_sec": 30 }
```

→ `{ "audioBase64": "...", "mime": "audio/mpeg", "durationSec": 30, "generationSeconds": 22.4 }`

`GET /healthz` — no auth, used by Cloud Run.

## Notes / alternatives

- The `pipeline(...)` keyword arguments in `main.py` track the ACE-Step v1
  repo; re-check them if the `acestep` package is upgraded.
- If Cloud Run L4 quota is slow to get, the fallback is a **GCE spot VM**
  (g2-standard-8, ~$0.25/hr spot) started/stopped with
  `gcloud compute instances start|stop` — but that *is* manual switching;
  Cloud Run's scale-to-zero is strictly better for the testing phase.
- Swapping the model later (e.g. a different HF text2music model) only touches
  this service; the proxy and the app never see the difference.

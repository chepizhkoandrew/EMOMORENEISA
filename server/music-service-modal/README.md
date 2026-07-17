# ACE-Step music service (Modal)

Self-hosted [ACE-Step](https://github.com/ace-step/ACE-Step) song generation, deployed on
[Modal](https://modal.com) instead of Cloud Run — Cloud Run's GPU-attached containers never
reliably received external traffic in this project (healthy container, zero requests routed to
it, reproduced across regions/frameworks/base images). Modal owns its own web-serving layer, so
there's no self-managed HTTP server to get that wrong.

## One-time setup

```
pip install modal
python3 -m modal setup                          # opens a browser to authenticate
modal secret create music-service-key MUSIC_SERVICE_KEY=<shared-secret>
```

The secret's value must match `MUSIC_SERVICE_KEY` in the Railway proxy's env — that's the
shared header (`X-API-Key`) gating every request.

## Deploy

```
modal deploy app.py
```

First deploy builds the image (installs deps, downloads the ~7GB model snapshot) — a few
minutes. Redeploys after code-only changes are fast (~1-2 min); changing `requirements`/pinned
versions invalidates the pip layer and re-downloads the model layer after it.

Prints two stable URLs:
- `.../ace-step-music-healthz.modal.run` (GET) — cheap, no GPU, doesn't load the model
- `.../ace-step-music-generate.modal.run` (POST) — the one Railway calls

Set on Railway: `MUSIC_SERVICE_URL=<generate URL>` `MUSIC_SERVICE_KEY=<same secret>`.

## Notes

- `diffusers` is pinned to `0.33.1` — ACE-Step's own requirements only floor it at `>=0.33.0`,
  and letting pip resolve to latest (0.39.x as of writing) breaks: newer `diffusers` registers a
  custom PyTorch op in a way incompatible with `torch==2.4.0` from the base image
  (`infer_schema(func): Parameter q has unsupported type torch.Tensor`). If you bump the base
  image's torch version, re-check whether this pin can be relaxed.
- `generate` is a `@modal.fastapi_endpoint` calling an `ACEStepService` class (`gpu="T4"`,
  `scaledown_window=300`) — the model loads once per container (`@modal.enter()`) and is reused
  across requests until the container scales to zero from inactivity.
- Modal's synchronous web-endpoint wrapper has its own internal wait deadline (~150s observed)
  before returning `303` with a `Location` poll URL instead of blocking further — the proxy
  (`server/src/music.js`) follows that explicitly rather than relying on `fetch`'s automatic
  redirect handling.
- Logs: `modal app logs ace-step-music`.

#!/usr/bin/env bash
# Deploys the ACE-Step music service to Cloud Run with an L4 GPU.
#
# Prereqs (one-time):
#   gcloud auth login && gcloud config set project "$PROJECT"
#   gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
#   Request "Cloud Run NVIDIA L4 GPU" quota in $REGION if not granted yet
#   (Cloud console -> IAM & Admin -> Quotas -> "Total Nvidia L4 GPU allocation, per project per region").
#
# Usage:
#   MUSIC_SERVICE_KEY=<shared-secret> ./deploy.sh
set -euo pipefail

PROJECT="${PROJECT:-$(gcloud config get-value project)}"
REGION="${REGION:-europe-west4}"          # L4 GPUs: us-central1, europe-west4, asia-southeast1, ...
SERVICE="${SERVICE:-ace-step-music}"
REPO="${REPO:-music-service}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${SERVICE}:latest"

if [[ -z "${MUSIC_SERVICE_KEY:-}" ]]; then
  echo "Set MUSIC_SERVICE_KEY (the shared secret the Railway proxy will send as X-API-Key)." >&2
  exit 1
fi

echo "==> Ensuring Artifact Registry repo ${REPO} exists"
gcloud artifacts repositories describe "${REPO}" --location "${REGION}" >/dev/null 2>&1 \
  || gcloud artifacts repositories create "${REPO}" --repository-format=docker --location "${REGION}"

echo "==> Building image (weights are baked in — first build downloads ~7 GB, allow ~30 min)"
gcloud builds submit --tag "${IMAGE}" --timeout=3600 --machine-type=e2-highcpu-8 .

echo "==> Deploying to Cloud Run (L4 GPU, scale-to-zero)"
gcloud run deploy "${SERVICE}" \
  --image "${IMAGE}" \
  --region "${REGION}" \
  --gpu 1 --gpu-type nvidia-l4 \
  --no-gpu-zonal-redundancy \
  --cpu 8 --memory 32Gi \
  --min-instances 0 --max-instances 1 \
  --concurrency 1 \
  --timeout 600 \
  --no-allow-unauthenticated \
  --set-env-vars "MUSIC_SERVICE_KEY=${MUSIC_SERVICE_KEY}"

echo
echo "Done. Service URL:"
gcloud run services describe "${SERVICE}" --region "${REGION}" --format 'value(status.url)'
echo
echo "Next steps:"
echo "  1. Allow the Railway proxy to call it. Simplest for the testing phase:"
echo "       gcloud run services add-iam-policy-binding ${SERVICE} --region ${REGION} \\"
echo "         --member=allUsers --role=roles/run.invoker"
echo "     (the X-API-Key shared secret still gates every request; switch to a"
echo "      service-account ID token before public launch)."
echo "  2. On Railway set: MUSIC_SERVICE_URL=<service url>  MUSIC_SERVICE_KEY=<same secret>"

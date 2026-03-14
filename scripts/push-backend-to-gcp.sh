#!/usr/bin/env bash
# Build backend image for linux/amd64 (GCP VM) and push to Artifact Registry.
# Avoids arch mismatch when building on Apple Silicon: buildx targets amd64 so the image runs on GCP.
# Prereq: gcloud auth configured and Docker authenticated (gcloud auth configure-docker REGION-docker.pkg.dev).
# Usage: ./scripts/push-backend-to-gcp.sh [TAG]
#   TAG defaults to "latest"; use e.g. "sha-$(git rev-parse --short HEAD)" for immutable deploys.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAG="${1:-latest}"

# Override with env if needed
GCP_PROJECT="${GCP_PROJECT:-manny-roy-consulting}"
ARTIFACT_REGION="${ARTIFACT_REGION:-northamerica-northeast1}"
REPO_NAME="${REPO_NAME:-docsgpt-repo}"
IMAGE_NAME="backend"
# Build for GCP VM (amd64); no mismatch when running on Compute Engine
PLATFORM="${PLATFORM:-linux/amd64}"
# If you see "No space left on device" during build: increase Docker Desktop disk image to at least 30GB.

FULL_IMAGE="${ARTIFACT_REGION}-docker.pkg.dev/${GCP_PROJECT}/${REPO_NAME}/${IMAGE_NAME}:${TAG}"

echo "Building backend for ${PLATFORM} and pushing to ${FULL_IMAGE}..."
docker buildx build \
  --platform "${PLATFORM}" \
  -f "${REPO_ROOT}/application/Dockerfile" \
  -t "${FULL_IMAGE}" \
  --push \
  "${REPO_ROOT}/application"

echo "Pushed ${FULL_IMAGE}"

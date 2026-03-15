#!/usr/bin/env bash
# Fetch app secrets from GCP Secret Manager and write to .env on the VM.
# Run on the VM (or via SSH during deploy). Requires gcloud and VM SA with roles/secretmanager.secretAccessor.
#
# Usage:
#   DEPLOY_PATH=/opt/docsgpt PROJECT_ID=my-project SECRET_NAME=docsgpt-env ./scripts/fetch-secrets-to-env.sh
# Or from /opt/docsgpt:  PROJECT_ID=manny-roy-consulting SECRET_NAME=docsgpt-env ./fetch-secrets-to-env.sh

set -e

DEPLOY_PATH="${DEPLOY_PATH:-/opt/docsgpt}"
PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID}"
SECRET_NAME="${SECRET_NAME:-docsgpt-env}"
ENV_FILE="${DEPLOY_PATH}/.env"

if ! command -v gcloud &>/dev/null; then
  echo "ERROR: gcloud not found. Install Google Cloud SDK on the VM." >&2
  exit 1
fi

# Write secret payload to .env (restrict permissions)
gcloud secrets versions access latest --secret="${SECRET_NAME}" --project="${PROJECT_ID}" > "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
echo "Wrote ${ENV_FILE} from secret ${SECRET_NAME}"

#!/usr/bin/env bash
#
# Add Canadian region resources when you already ran gcp-setup.sh in another region.
# Creates: Artifact Registry in Montréal, Docker auth, optional VM in northamerica-northeast1-a.
# Does not delete existing us-central1 (or other) resources.
#
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Canadian region (Montréal)
ARTIFACT_REGION="${ARTIFACT_REGION:-northamerica-northeast1}"
ARTIFACT_REPO_NAME="${ARTIFACT_REPO_NAME:-docsgpt-repo}"
VM_ZONE="${VM_ZONE:-northamerica-northeast1-a}"
VM_NAME="${VM_NAME:-docsgpt-prod-ca}"   # different name so it doesn't clash with existing VM

GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
if [ -z "$GCP_PROJECT" ]; then
    echo -e "${RED}No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID${NC}"
    echo "Or: GCP_PROJECT=manny-roy-consulting ./scripts/gcp-add-canada.sh"
    exit 1
fi

echo -e "${BOLD}Adding Canadian region (Montréal) for DocsGPT${NC}"
echo "Project: $GCP_PROJECT"
echo "Region:  $ARTIFACT_REGION (Montréal)"
echo

# Enable APIs in the region (project-level)
for api in artifactregistry.googleapis.com compute.googleapis.com; do
    gcloud services enable "$api" --project="$GCP_PROJECT" 2>/dev/null || true
done

# Artifact Registry in Canada
if gcloud artifacts repositories describe "$ARTIFACT_REPO_NAME" --location="$ARTIFACT_REGION" --project="$GCP_PROJECT" &>/dev/null; then
    echo -e "${GREEN}✓ Artifact Registry ${ARTIFACT_REPO_NAME} already exists in ${ARTIFACT_REGION}${NC}"
else
    echo "Creating Artifact Registry: ${ARTIFACT_REPO_NAME} in ${ARTIFACT_REGION}..."
    gcloud artifacts repositories create "$ARTIFACT_REPO_NAME" \
        --repository-format=docker \
        --location="$ARTIFACT_REGION" \
        --description="DocsGPT Docker images (Canada)" \
        --project="$GCP_PROJECT"
    echo -e "${GREEN}✓ Artifact Registry created${NC}"
fi

REGISTRY_HOST="${ARTIFACT_REGION}-docker.pkg.dev"
echo "Configuring Docker for ${REGISTRY_HOST}..."
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet
echo -e "${GREEN}✓ Docker configured for Canadian registry${NC}"

# Optional VM in Canada
echo
read -p "Create a VM in Canada (${VM_ZONE})? Use this for DocsGPT instead of the US VM. (y/N): " do_vm
if [[ "$do_vm" =~ ^[yY]$ ]]; then
    echo "Creating VM: $VM_NAME in $VM_ZONE..."
    gcloud compute instances create "$VM_NAME" \
        --zone="$VM_ZONE" \
        --machine-type=e2-standard-2 \
        --image-family=ubuntu-2204-lts \
        --image-project=ubuntu-os-cloud \
        --tags=https-server,http-server \
        --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y docker.io docker-compose-plugin
systemctl enable docker && systemctl start docker
usermod -aG docker ubuntu 2>/dev/null || true
' \
        --project="$GCP_PROJECT"
    echo -e "${GREEN}✓ VM created: $VM_NAME${NC}"
    echo "  SSH: gcloud compute ssh $VM_NAME --zone=$VM_ZONE"
fi

echo
echo -e "${BOLD}Canadian region ready.${NC}"
echo "Use this registry for image push (Montréal):"
echo "  ${REGISTRY_HOST}/${GCP_PROJECT}/${ARTIFACT_REPO_NAME}/<name>:latest"
echo
echo "To use only Canadian resources: push images here and deploy on the Canadian VM (if you created one)."
echo "Your existing US resources (Artifact Registry, VM) are unchanged; you can delete them from the GCP console if you no longer need them."

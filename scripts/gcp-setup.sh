#!/usr/bin/env bash
#
# GCP pre-setup for DocsGPT (DevOps showcase).
# Run this script BEFORE ./setup.sh when deploying to Google Cloud.
# Sets up: gcloud auth, project, Artifact Registry, Docker auth. Optionally creates VM.
#
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Config (override with env or edit)
GCP_PROJECT="${GCP_PROJECT:-}"
ARTIFACT_REGION="${ARTIFACT_REGION:-northamerica-northeast1}"
ARTIFACT_REPO_NAME="${ARTIFACT_REPO_NAME:-docsgpt-repo}"
VM_ZONE="${VM_ZONE:-northamerica-northeast1-a}"
VM_NAME="${VM_NAME:-docsgpt-prod}"
VM_BOOT_DISK_GB="${VM_BOOT_DISK_GB:-50}"

echo -e "${BOLD}DocsGPT – GCP pre-setup (DevOps)${NC}"
echo "This script configures gcloud and GCP resources before you run ./setup.sh"
echo

# --- 1. Check gcloud CLI ---
if ! command -v gcloud &>/dev/null; then
    echo -e "${RED}gcloud CLI is not installed.${NC}"
    echo "Install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "${GREEN}✓ gcloud CLI found${NC}"

# --- 2. Auth ---
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 | grep -q .; then
    echo -e "${YELLOW}No active gcloud account. Running: gcloud auth login${NC}"
    gcloud auth login
fi
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
echo -e "${GREEN}✓ gcloud authenticated${NC}"
echo -e "  Account: ${CURRENT_ACCOUNT}"
echo -e "  Current project: ${CURRENT_PROJECT:-<not set>}"
echo

# --- 3. Project ---
if [ -z "$GCP_PROJECT" ]; then
    if [ -n "$CURRENT_PROJECT" ]; then
        echo "Use the project above, or enter a different project ID (e.g. manny-roy-consulting)."
        read -p "GCP project ID [${CURRENT_PROJECT}]: " input_project
        if [ -z "$input_project" ]; then
            GCP_PROJECT="$CURRENT_PROJECT"
        else
            GCP_PROJECT="$input_project"
        fi
    else
        echo "Available projects for this account:"
        gcloud projects list --format="table(projectId,name)" 2>/dev/null || true
        read -p "Enter GCP project ID: " GCP_PROJECT
    fi
fi
if [ -z "$GCP_PROJECT" ]; then
    echo -e "${RED}GCP project ID is required. Set GCP_PROJECT or enter it when prompted.${NC}"
    exit 1
fi
gcloud config set project "$GCP_PROJECT" 2>/dev/null || true
if ! gcloud projects describe "$GCP_PROJECT" &>/dev/null; then
    echo -e "${RED}The current account does not have access to project: ${GCP_PROJECT}${NC}"
    echo -e "${YELLOW}Log in with an account that has access to that project:${NC}"
    echo "  gcloud auth login"
    echo "Then re-run this script, or run: GCP_PROJECT=manny-roy-consulting ./scripts/gcp-setup.sh"
    exit 1
fi
echo -e "${GREEN}✓ Project set to ${GCP_PROJECT}${NC}"

# --- 4. Enable APIs (Artifact Registry, Compute) ---
echo "Enabling required APIs..."
for api in artifactregistry.googleapis.com compute.googleapis.com; do
    gcloud services enable "$api" --project="$GCP_PROJECT" 2>/dev/null || true
done
echo -e "${GREEN}✓ APIs enabled${NC}"

# --- 5. Artifact Registry ---
if gcloud artifacts repositories describe "$ARTIFACT_REPO_NAME" --location="$ARTIFACT_REGION" --project="$GCP_PROJECT" &>/dev/null; then
    echo -e "${GREEN}✓ Artifact Registry repository ${ARTIFACT_REPO_NAME} already exists${NC}"
else
    echo "Creating Artifact Registry repository: ${ARTIFACT_REPO_NAME} in ${ARTIFACT_REGION}"
    gcloud artifacts repositories create "$ARTIFACT_REPO_NAME" \
        --repository-format=docker \
        --location="$ARTIFACT_REGION" \
        --description="DocsGPT Docker images" \
        --project="$GCP_PROJECT"
    echo -e "${GREEN}✓ Artifact Registry created${NC}"
fi

# --- 6. Docker auth to Artifact Registry ---
REGISTRY_HOST="${ARTIFACT_REGION}-docker.pkg.dev"
echo "Configuring Docker for ${REGISTRY_HOST}..."
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet
echo -e "${GREEN}✓ Docker configured for Artifact Registry${NC}"

# --- 7. Optional: Create Compute Engine VM ---
create_vm() {
    echo
    read -p "Create Compute Engine VM for DocsGPT? (y/N): " do_vm
    if [[ ! "$do_vm" =~ ^[yY]$ ]]; then
        return 0
    fi
    echo "Creating VM: $VM_NAME in $VM_ZONE (e2-standard-2, Ubuntu 22.04, ${VM_BOOT_DISK_GB}GB disk)..."
    gcloud compute instances create "$VM_NAME" \
        --zone="$VM_ZONE" \
        --machine-type=e2-standard-2 \
        --boot-disk-size="${VM_BOOT_DISK_GB}GB" \
        --image-family=ubuntu-2204-lts \
        --image-project=ubuntu-os-cloud \
        --tags=https-server,http-server \
        --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y docker.io docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu 2>/dev/null || true
' \
        --project="$GCP_PROJECT"
    echo -e "${GREEN}✓ VM created. Allow a few minutes for Docker to be ready.${NC}"
    echo "  SSH: gcloud compute ssh $VM_NAME --zone=$VM_ZONE"
}

create_vm

# --- Summary ---
echo
echo -e "${BOLD}GCP pre-setup complete.${NC}"
echo
echo "Next steps:"
echo "  1. Run DocsGPT setup:  cd \"${REPO_ROOT}\" && ./setup.sh"
echo "  2. In advanced settings, choose:"
echo "     - Vector Store: Qdrant  →  QDRANT_URL=http://qdrant:6333 (for Docker on VM)"
echo "     - Authentication: Simple JWT or Session JWT (recommended for production)"
echo "  3. For deployment on the VM, use the compose file that includes Qdrant:"
echo "     deployment/docker-compose.gcp.yaml"
echo "  4. Image push (after building):"
echo "     docker tag <image> ${REGISTRY_HOST}/${GCP_PROJECT}/${ARTIFACT_REPO_NAME}/<name>:latest"
echo "     docker push ${REGISTRY_HOST}/${GCP_PROJECT}/${ARTIFACT_REPO_NAME}/<name>:latest"
echo
echo "Full guide: docs/GCP-DEVOPS-SETUP.md"

#!/usr/bin/env bash
#
# Delete DocsGPT resources created in us-central1 so you can use Canadian regions instead.
# Removes: VM (docsgpt-prod in us-central1-a), Artifact Registry repo (docsgpt-repo in us-central1).
# Run this first, then run ./scripts/gcp-setup.sh to create resources in northamerica-northeast1.
#
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# US region/zone and resource names (from initial setup)
US_REGION="${US_REGION:-us-central1}"
US_ZONE="${US_ZONE:-us-central1-a}"
US_VM_NAME="${US_VM_NAME:-docsgpt-prod}"
US_REPO_NAME="${US_REPO_NAME:-docsgpt-repo}"

GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
if [ -z "$GCP_PROJECT" ]; then
    echo -e "${RED}No GCP project set. Set GCP_PROJECT or run: gcloud config set project YOUR_PROJECT_ID${NC}"
    exit 1
fi

echo -e "${BOLD}Delete US region DocsGPT resources${NC}"
echo "Project:    $GCP_PROJECT"
echo "Zone:       $US_ZONE (VM: $US_VM_NAME)"
echo "Region:     $US_REGION (Artifact Registry: $US_REPO_NAME)"
echo
echo -e "${YELLOW}This will delete the VM and Artifact Registry repo in us-central1.${NC}"
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Delete VM
if gcloud compute instances describe "$US_VM_NAME" --zone="$US_ZONE" --project="$GCP_PROJECT" &>/dev/null; then
    echo "Deleting VM $US_VM_NAME in $US_ZONE..."
    gcloud compute instances delete "$US_VM_NAME" --zone="$US_ZONE" --project="$GCP_PROJECT" --quiet
    echo -e "${GREEN}✓ VM deleted${NC}"
else
    echo "VM $US_VM_NAME not found in $US_ZONE (skipping)."
fi

# Delete Artifact Registry repo
if gcloud artifacts repositories describe "$US_REPO_NAME" --location="$US_REGION" --project="$GCP_PROJECT" &>/dev/null; then
    echo "Deleting Artifact Registry repository $US_REPO_NAME in $US_REGION..."
    gcloud artifacts repositories delete "$US_REPO_NAME" --location="$US_REGION" --project="$GCP_PROJECT" --quiet
    echo -e "${GREEN}✓ Artifact Registry repository deleted${NC}"
else
    echo "Artifact Registry repository $US_REPO_NAME not found in $US_REGION (skipping)."
fi

echo
echo -e "${GREEN}US resources removed.${NC}"
echo "Next: run the main setup to create resources in Canadian region (Montréal):"
echo "  GCP_PROJECT=$GCP_PROJECT ./scripts/gcp-setup.sh"
echo "(Canadian region is the default in gcp-setup.sh.)"

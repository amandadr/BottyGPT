# DocsGPT on Google Cloud (GCP) – DevOps showcase

This guide walks through running DocsGPT on GCP with **Qdrant** as the vector store, suitable for demonstrating DevOps and cloud engineering skills.

## Prerequisites

- [Google Cloud SDK (gcloud)](https://cloud.google.com/sdk/docs/install) installed and in `PATH`

**Region:** The script and examples use Canadian regions by default: **northamerica-northeast1** (Montréal) and zone **northamerica-northeast1-a**. For Toronto use `northamerica-northeast2` and `northamerica-northeast2-a`.

- A GCP project with billing enabled
- Docker installed locally (for building images). If you see "No space left on device" during `pip install` in a build, increase Docker Desktop’s virtual disk to at least **30GB** (Settings → Resources → Advanced → Virtual disk limit).

## Step 0: Run GCP pre-setup **before** DocsGPT setup

From the repo root, run the GCP pre-setup script **first**:

```bash
./scripts/gcp-setup.sh
```

This script will:

1. Check and authenticate `gcloud`
2. Set or prompt for your GCP project
3. Enable Artifact Registry and Compute APIs
4. Create an Artifact Registry repository (e.g. `docsgpt-repo` in `northamerica-northeast1`, Montréal)
5. Configure Docker to push to `northamerica-northeast1-docker.pkg.dev`
6. Optionally create a Compute Engine VM for running the stack (**50GB boot disk** by default; set `VM_BOOT_DISK_GB` to override)

**Already ran setup in us-central1 and want to use only Canadian regions?** Delete the US resources, then run the main setup (which uses Canadian regions by default):

```bash
# 1. Delete VM and Artifact Registry in us-central1
GCP_PROJECT=manny-roy-consulting ./scripts/gcp-delete-us-resources.sh

# 2. Create resources in Montréal (default in gcp-setup.sh)
GCP_PROJECT=manny-roy-consulting ./scripts/gcp-setup.sh
```

**Want to keep US resources and add Canadian ones?** Use `./scripts/gcp-add-canada.sh` to create an Artifact Registry and optional VM in Montréal without deleting existing US resources.

You can override defaults with environment variables:

```bash
GCP_PROJECT=my-project ARTIFACT_REGION=northamerica-northeast1 ./scripts/gcp-setup.sh
```

## Step 1: Run DocsGPT setup

After GCP pre-setup:

```bash
./setup.sh
```

When you reach **Advanced settings**:

- **Vector Store:** choose **Qdrant**
  - **Qdrant URL:** `http://qdrant:6333` (when using Docker Compose on the VM; the hostname `qdrant` is the service name)
  - For local runs with the GCP compose file, use `http://qdrant:6333` as well
- **Authentication:** choose **Simple JWT** or **Session JWT** for production
- Save and continue with Docker setup.

## Required GCP services (overview)

| Service | Purpose |
|--------|---------|
| **Artifact Registry** | Store your built Docker images (frontend, backend, etc.) |
| **Compute Engine (VM)** | Run the multi-container DocsGPT stack (app + Qdrant + Redis + Mongo) |
| **Cloud Load Balancing + Managed Certificates** (optional) | HTTPS for your domains without managing Let’s Encrypt on the VM |
| **Cloud SQL** (optional) | Only if you switch from Qdrant to **PGVector** |

## Step 2: Configuring DocsGPT for Qdrant

When using the **Docker Compose** stack (e.g. on the VM), backend and worker talk to Qdrant over the Docker network. In `.env`:

```env
VECTOR_STORE=qdrant
QDRANT_URL=http://qdrant:6333
QDRANT_COLLECTION_NAME=docsgpt
```

If you run Qdrant elsewhere, set `QDRANT_URL` to that host (e.g. `http://<qdrant-host>:6333`).

## Step 3: Deploying on the VM with Qdrant

Use the compose file that includes the Qdrant service:

```bash
docker compose -f deployment/docker-compose.gcp.yaml --env-file .env up -d
```

That file defines the `qdrant` service and sets backend/worker to use `http://qdrant:6333`.

## Step 4: CORS when embedding on your domains

If you embed the DocsGPT UI or API on **mannyroy.com** and **docs.mannyroy.com**, configure CORS so the backend allows requests from those origins.

The app currently sends `Access-Control-Allow-Origin: *`. For production you can restrict origins by:

- Adding an optional `ALLOWED_ORIGINS` (or similar) in your backend and setting it in `.env`, **or**
- Using a reverse proxy (e.g. Cloud Load Balancer, nginx) to add restrictive CORS headers.

Example if you add support for `ALLOWED_ORIGINS` in the app:

```env
# Optional: comma-separated list of allowed frontend origins
ALLOWED_ORIGINS=https://mannyroy.com,https://docs.mannyroy.com
```

## Step 5: Vite and frontend (production)

The **Dashboard** is the React app built with Vite. For production on GCP:

- **Dashboard:** `https://assistant.mannyroy.com` (served by Nginx in Docker)
- **API:** `https://assistant-api.mannyroy.com` (Flask backend)

**Environment variables** (in `frontend/.env.production` or as Docker build args):

- `VITE_API_HOST` – backend API URL (e.g. `https://assistant-api.mannyroy.com`)
- `VITE_API_STREAMING` – `true` for streaming answers
- `VITE_BASE_URL` – dashboard URL (e.g. `https://assistant.mannyroy.com`)

The repo includes:

- **`frontend/.env.production`** – pre-set for assistant/assistant-api.mannyroy.com
- **`frontend/vite.config.ts`** – `base: '/'`, build output `dist/`, sourcemaps, and dev proxy to `localhost:7091`
- **`frontend/Dockerfile.production`** – multi-stage: Node build → Nginx serving static files
- **`frontend/nginx.conf`** – SPA fallback (`try_files ... /index.html`) and gzip

**GCP compose:** `deployment/docker-compose.gcp.yaml` builds the frontend with `Dockerfile.production` and exposes port 80. Override URLs with env when building:

```bash
VITE_API_HOST=https://assistant-api.mannyroy.com VITE_BASE_URL=https://assistant.mannyroy.com \
  docker compose -f deployment/docker-compose.gcp.yaml --env-file .env up -d --build
```

**Widget embed:** For Ghost and Docusaurus, the embed script should point to your backend or to the widget asset served by your stack (e.g. from the same Nginx or backend).

**Docker Compose logs:** The backend service is named `backend`, not `api`. Use:

```bash
docker compose -f deployment/docker-compose.gcp.yaml logs backend
```

## Step 6: Artifact Registry – build and push images

After building your images locally (or in CI), tag and push them to your Artifact Registry:

```bash
# Replace with your project and repo
REGISTRY=northamerica-northeast1-docker.pkg.dev/YOUR_PROJECT_ID/docsgpt-repo

docker tag docsgpt-backend:latest $REGISTRY/backend:latest
docker tag docsgpt-frontend:latest $REGISTRY/frontend:latest
docker push $REGISTRY/backend:latest
docker push $REGISTRY/frontend:latest
```

On the VM, pull from the same registry and run the stack (e.g. with `docker-compose.gcp.yaml`).

## Step 7: VM startup (optional automation)

You can use a startup script so the VM installs Docker and (optionally) pulls and runs your stack. Example (customize image names and compose path):

```bash
gcloud compute instances create docsgpt-prod \
  --zone=northamerica-northeast1-a \
  --machine-type=e2-standard-2 \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --tags=https-server,http-server \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y docker.io docker-compose-plugin
gcloud auth configure-docker northamerica-northeast1-docker.pkg.dev --quiet
# Add your logic to pull images and run: docker compose -f deployment/docker-compose.gcp.yaml up -d
'
```

For real deployments, prefer pulling images and env from a secure store (e.g. Secret Manager, GCS) and running compose from there.

## Infrastructure as Code (IaC) – “show-off” tip

To demonstrate full-stack DevOps:

1. **Terraform** (or similar) to define:
   - VPC and firewall rules
   - Compute Engine instance(s)
   - Artifact Registry repository
   - Optional: Load balancer, managed certs, Cloud SQL if using PGVector

2. **CI/CD (e.g. GitHub Actions)** to:
   - Build Docker images
   - Push to Artifact Registry
   - Deploy to the VM (e.g. SSH + `docker compose pull && docker compose up -d`) or trigger a pipeline that does the same

This shows you can deploy and maintain an LLM app on GCP with production-style tooling.

## Quick reference

| What | Command / value |
|------|-------------------|
| GCP pre-setup | `./scripts/gcp-setup.sh` |
| DocsGPT setup | `./setup.sh` → Advanced → Vector Store: Qdrant, `QDRANT_URL=http://qdrant:6333` |
| Compose on VM | `docker compose -f deployment/docker-compose.gcp.yaml --env-file .env up -d` |
| CORS (if supported) | `ALLOWED_ORIGINS=https://mannyroy.com,https://docs.mannyroy.com` |

# GitHub Actions: Push-to-Deploy

The **Deploy to GCP (Cloud Run + VM)** workflow (`.github/workflows/deploy.yml`) builds backend and frontend, pushes both to Artifact Registry, deploys the **frontend to Cloud Run**, and deploys the **backend stack on the VM** (Compose).

## Flow

1. **Trigger:** Push to `main` (or run manually via **Actions → Deploy to GCP (Cloud Run + VM) → Run workflow**). Paths under `docs/**`, `**.md`, and `google-cloud-sdk/**` are ignored.
2. **Build:** Backend and frontend are built for `linux/amd64` and pushed to Artifact Registry with tag `github.sha`.
3. **Deploy frontend:** The frontend image is deployed to **Cloud Run** (service `docsgpt-frontend`). See [CLOUD-RUN-SETUP.md](CLOUD-RUN-SETUP.md) for one-time setup.
4. **Deploy backend:** Workflow SSHs to the VM, sets `IMAGE_TAG=<sha>` in `.env`, then runs `docker compose pull` and `up -d` (backend, worker, Redis, Mongo, Qdrant only; no frontend on the VM).

## Required secrets

In **GitHub → Repository → Settings → Secrets and variables → Actions**, add:

| Secret | Description |
|--------|-------------|
| `GCP_SA_KEY` | JSON key for `gh-actions-sa`. The SA needs **Artifact Registry Writer**, **Cloud Run Admin** (see [CLOUD-RUN-SETUP.md](CLOUD-RUN-SETUP.md)), and enough access for the VM (e.g. **Compute Instance Admin** if you use gcloud for SSH, or just SSH keys). |
| `VM_IP` | Public IP (or hostname) of the GCP VM (backend). |
| `VM_USER` | SSH user (e.g. your Google username or `ubuntu` depending on the image). |
| `SSH_PRIVATE_KEY` | Private key that can log in as `VM_USER` to `VM_IP`. Add the public key to the VM’s `~/.ssh/authorized_keys`. |

Optional (for frontend build URLs):

| Secret | Description |
|--------|-------------|
| `VITE_API_HOST` | Override API URL (default `https://assistant-api.mannyroy.com`). |
| `VITE_BASE_URL` | Override app URL (default `https://assistant.mannyroy.com`). |

## VM setup (backend only)

The VM runs **only** the backend stack (no frontend container). Frontend is on Cloud Run.

1. **Deploy path:** The workflow runs from `DEPLOY_PATH` (default `/opt/docsgpt`). That directory must contain:
   - `.env` (app secrets; the workflow only adds/updates `IMAGE_TAG`).
   - `docker-compose.gcp.yaml` (VM-only compose: backend, worker, Redis, Mongo, Qdrant). Copy from repo `deployment/docker-compose.gcp.yaml`.
2. **Docker:** Docker and Docker Compose plugin installed; deploy user can run `docker compose` without sudo.
3. **Artifact Registry:** VM can pull backend images (e.g. default SA with **Artifact Registry Reader**, or `gcloud auth configure-docker REGION-docker.pkg.dev`).

## Immutable images

Every deploy uses the commit SHA as the image tag. To roll back:
- **Backend (VM):** Set `IMAGE_TAG=<previous-sha>` in `.env` on the VM and run `docker compose -f docker-compose.gcp.yaml --env-file .env up -d`.
- **Frontend (Cloud Run):** Redeploy a previous image tag in Cloud Run or re-run the workflow from an earlier commit.

## Switching to Workload Identity Federation

To avoid storing a JSON key in `GCP_SA_KEY`, use [Workload Identity Federation](https://github.com/google-github-actions/auth#usage-with-workload-identity-federation). In the workflow, replace the `auth` step with the OIDC variant and remove `GCP_SA_KEY` from secrets.

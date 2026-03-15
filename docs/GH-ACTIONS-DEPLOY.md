# GitHub Actions: Push-to-Deploy

The **Deploy to GCP (VM)** workflow (`.github/workflows/deploy.yml`) builds backend and frontend, pushes both to Artifact Registry, then deploys the **full stack on the VM** (frontend + backend + worker + Redis + Mongo + Qdrant) via SSH and Docker Compose.

## Flow

1. **Trigger:** Push to `main` (or run manually via **Actions → Deploy to GCP (VM) → Run workflow**). Paths under `docs/**`, `**.md`, and `google-cloud-sdk/**` are ignored. On manual run you can set **Reuse image tag** to skip build and only run VM deploy.
2. **Build:** Backend and frontend are built for `linux/amd64` and pushed to Artifact Registry with tag `github.sha` (skipped when reusing a tag).
3. **Deploy on VM:** Workflow SSHs to the VM, sets `IMAGE_TAG=<sha or reused tag>` in `.env`, then runs `docker compose pull` and `up -d` for the full stack (frontend on port 80, backend on 7091, worker, Redis, Mongo, Qdrant).

## Required secrets

In **GitHub → Repository → Settings → Secrets and variables → Actions**, add:

| Secret | Description |
|--------|-------------|
| `GCP_SA_KEY` | JSON key for the CI service account. The SA needs **Artifact Registry Writer** and enough access for the VM (e.g. **Compute Instance Admin** if you use gcloud for SSH, or just SSH keys). |
| `VM_IP` | Public IP (or hostname) of the GCP VM. |
| `VM_USER` | SSH user (e.g. your Google username or `ubuntu` depending on the image). |
| `SSH_PRIVATE_KEY` | Private key that can log in as `VM_USER` to `VM_IP`. Add the public key to the VM’s `~/.ssh/authorized_keys`. |

Optional (for frontend build; used as build-args for the frontend image):

| Secret | Description |
|--------|-------------|
| `VITE_API_HOST` | API URL the browser will use (default `https://assistant-api.mannyroy.com`). |
| `VITE_BASE_URL` | App URL for redirects/cookies (default `https://assistant.mannyroy.com`). |

## VM setup

The VM runs the **full stack**: frontend (port 80), backend (7091), worker, Redis, Mongo, Qdrant.

1. **Deploy path:** The workflow runs from `DEPLOY_PATH` (default `/opt/docsgpt`). That directory must contain:
   - `.env` (app secrets; the workflow only adds/updates `IMAGE_TAG`).
   - `docker-compose.gcp.yaml` (full stack). Copy from repo `deployment/docker-compose.gcp.yaml`.
2. **Docker:** Docker and Docker Compose plugin installed; the deploy user can run `docker compose` (workflow uses `sudo docker compose`).
3. **Artifact Registry:** VM can pull backend and frontend images. See **Troubleshooting** below if `docker compose pull` fails with auth errors.
4. **Firewall:** Open port 80 (or whatever you set in `FRONTEND_HOST_PORT`, default 80) and 7091 if you expose the API directly, or put a reverse proxy in front.

### Port 80 already in use

If deploy fails with `Bind for :::80 failed: port is already allocated`, something else (e.g. nginx for TLS) owns port 80. On the VM, add to `.env`:

```env
FRONTEND_HOST_PORT=8080
```

Then `sudo docker compose ... up -d` again. Open the UI at `http://VM_IP:8080`, or point nginx at `127.0.0.1:8080` instead of 80.

## Troubleshooting

### VM: "Reauthentication failed" or "cannot prompt during non-interactive execution" on `docker compose pull`

The VM’s Docker credential helper is using credentials that require an interactive login. Fix it so the VM uses its **Compute Engine service account** to pull from Artifact Registry:

1. **Grant the VM’s service account access to Artifact Registry** (from your Mac or Cloud Shell):
   ```bash
   PROJECT_ID=manny-roy-consulting
   PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
   gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
     --role="roles/artifactregistry.reader"
   ```

2. **On the VM**, ensure Docker uses the instance’s credentials (no interactive login). The workflow script logs in via GCE metadata and strips `credHelpers` for the registry; if you run compose manually, use the same token login or the **GCE metadata credential helper** (see repo scripts or docs).

Re-run the workflow; to avoid rebuilding, use **Actions → Deploy to GCP (VM) → Run workflow** and set **Reuse image tag** to the tag that already built (e.g. the commit SHA).

## Immutable images

Every deploy uses the commit SHA as the image tag. To roll back:

- Set `IMAGE_TAG=<previous-sha>` in `.env` on the VM and run:
  `sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d`

## Switching to Workload Identity Federation

To avoid storing a JSON key in `GCP_SA_KEY`, use [Workload Identity Federation](https://github.com/google-github-actions/auth#usage-with-workload-identity-federation). In the workflow, replace the `auth` step with the OIDC variant and remove `GCP_SA_KEY` from secrets.

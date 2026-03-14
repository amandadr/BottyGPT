# GitHub Actions: Push-to-Deploy

The **Deploy to GCP (Cloud Run + VM)** workflow (`.github/workflows/deploy.yml`) builds backend and frontend, pushes both to Artifact Registry, deploys the **frontend to Cloud Run**, and deploys the **backend stack on the VM** (Compose).

## Flow

1. **Trigger:** Push to `main` (or run manually via **Actions → Deploy to GCP (Cloud Run + VM) → Run workflow**). Paths under `docs/**`, `**.md`, and `google-cloud-sdk/**` are ignored. On manual run you can set **Reuse image tag** to skip build and only run VM deploy (e.g. after fixing VM auth).
2. **Build:** Backend and frontend are built for `linux/amd64` and pushed to Artifact Registry with tag `github.sha` (skipped when reusing a tag).
3. **Deploy frontend:** The frontend image is deployed to **Cloud Run** (service `docsgpt-frontend`). See [CLOUD-RUN-SETUP.md](CLOUD-RUN-SETUP.md) for one-time setup.
4. **Deploy backend:** Workflow SSHs to the VM, sets `IMAGE_TAG=<sha or reused tag>` in `.env`, then runs `docker compose pull` and `up -d` (backend, worker, Redis, Mongo, Qdrant only; no frontend on the VM).

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
3. **Artifact Registry:** VM can pull backend images. See **Troubleshooting** below if `docker compose pull` fails with auth errors.

## Troubleshooting

### VM: "Reauthentication failed" or "cannot prompt during non-interactive execution" on `docker compose pull`

The VM’s Docker credential helper is using credentials that require an interactive login (e.g. from a past `gcloud auth login`). Fix it so the VM uses its **Compute Engine service account** to pull from Artifact Registry:

1. **Grant the VM’s service account access to Artifact Registry** (from your Mac or Cloud Shell):
   ```bash
   PROJECT_ID=manny-roy-consulting
   PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
   gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
     --role="roles/artifactregistry.reader"
   ```

2. **On the VM**, use the instance’s credentials for Docker (no interactive login):
   - If you ever ran `gcloud auth login` on the VM, revoke it so the default is the instance SA:  
     `gcloud auth revoke --all`  
     (Then only use the VM for deploy; don’t log in again with your user.)
   - Configure Docker to use Artifact Registry (run as the user that runs `docker compose`):
     ```bash
     gcloud auth configure-docker northamerica-northeast1-docker.pkg.dev --quiet
     ```
   If `gcloud` isn’t installed on the VM, install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) or use a VM image that includes it.

**Preferred (no credentials on disk):** Use the **GCE metadata credential helper** so Docker fetches tokens on demand and never stores them:

```bash
# One-time: install helper and point Docker at it
mkdir -p /opt/docsgpt/bin
# Copy from repo or download (replace COMMIT_SHA with a commit that has the script)
curl -sSL "https://raw.githubusercontent.com/amandadr/BottyGPT/main/scripts/docker-credential-gce-metadata" -o /opt/docsgpt/bin/docker-credential-gce-metadata
chmod +x /opt/docsgpt/bin/docker-credential-gce-metadata
export PATH="/opt/docsgpt/bin:$PATH"
python3 -c "
import json, os
path = os.path.expanduser('~/.docker/config.json')
with open(path) as f: c = json.load(f)
c.setdefault('credHelpers', {})['northamerica-northeast1-docker.pkg.dev'] = 'gce-metadata'
# Remove any stored auth for this registry
for k in list(c.get('auths', {})):
    if 'northamerica-northeast1-docker.pkg.dev' in k:
        del c['auths'][k]
with open(path, 'w') as f: json.dump(c, f, indent=2)
"
echo 'export PATH="/opt/docsgpt/bin:$PATH"' >> ~/.bashrc
```

Then run `docker compose pull` and `up -d`. The workflow installs and uses this helper automatically on each deploy, so no credentials are stored.

Re-run the workflow; to avoid rebuilding, use **Actions → Deploy to GCP (Cloud Run + VM) → Run workflow** and set **Reuse image tag** to the tag that already built (e.g. `9fe4e5c77af5739962c9a0e1acaa2dae1d01ce41`).

## Immutable images

Every deploy uses the commit SHA as the image tag. To roll back:
- **Backend (VM):** Set `IMAGE_TAG=<previous-sha>` in `.env` on the VM and run `docker compose -f docker-compose.gcp.yaml --env-file .env up -d`.
- **Frontend (Cloud Run):** Redeploy a previous image tag in Cloud Run or re-run the workflow from an earlier commit.

## Switching to Workload Identity Federation

To avoid storing a JSON key in `GCP_SA_KEY`, use [Workload Identity Federation](https://github.com/google-github-actions/auth#usage-with-workload-identity-federation). In the workflow, replace the `auth` step with the OIDC variant and remove `GCP_SA_KEY` from secrets.

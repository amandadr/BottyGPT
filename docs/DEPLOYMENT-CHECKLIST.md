# Plan 2.0: Fresh VM deployment checklist

Use this checklist when provisioning a new VM for the **full stack** (frontend + backend + worker + Redis + Mongo + Qdrant). The GitHub Actions workflow builds both images, pushes to Artifact Registry, and deploys everything on the VM. Do **not** build backend/frontend on the VM; use CI-built images only.

**Production setup in use:** [Secret Manager](SECRET-MANAGER-SETUP.md) (app secrets fetched on deploy when `USE_SECRET_MANAGER=true`) and [Cloud Logging](CLOUD-LOGGING-SETUP.md) (Ops Agent sends Docker container logs to Cloud Logging).

## Continue deployment

1. **GitHub secrets** – In the repo: **Settings → Secrets and variables → Actions**. Required: `GCP_SA_KEY`, `VM_IP`, `VM_USER`, `SSH_PRIVATE_KEY`. Optional: `VITE_API_HOST`, `VITE_BASE_URL`, `USE_TLS`, **`USE_SECRET_MANAGER`** (set to `true` to fetch app secrets from Secret Manager on each deploy; see [SECRET-MANAGER-SETUP.md](SECRET-MANAGER-SETUP.md)).
2. **VM ready** – VM exists, Docker + Compose installed, `/opt/docsgpt` has `.env` and `docker-compose.gcp.yaml` (full stack from repo). If **USE_SECRET_MANAGER** is true, the workflow populates `.env` from Secret Manager; otherwise ensure `.env` is present. The user that `VM_USER` logs in as can run `docker compose` (e.g. in `docker` group). VM can pull from Artifact Registry (default Compute SA has Artifact Registry Reader, or use metadata-based login).
3. **Trigger deploy** – Push to `main` or go to **Actions → Deploy to GCP (VM) → Run workflow**. The workflow will build both images, then SSH to the VM and run `compose pull` / `up -d`.
4. **Validate** – Open the frontend (VM IP:80 or your domain), hit the API (VM IP:7091 or assistant-api.mannyroy.com), run the acceptance checks below.

## Pre-requisites

- [ ] Preflight CI has passed.
- [ ] Backend and frontend images are in Artifact Registry (workflow or manual push).
- [ ] `.env` and full-stack Compose file (`docker-compose.gcp.yaml`) are ready to copy to the VM.

## 1. Provision VM

- [ ] Create a new Compute Engine VM with **50GB boot disk** (e.g. `--boot-disk-size=50GB` if using gcloud).
- [ ] Open firewall for frontend (80) and API (e.g. 7091), or put a reverse proxy/load balancer in front with TLS.
- [ ] SSH access configured (e.g. `gcloud compute ssh <instance> --zone=...`).

## 2. Install runtime only

On the VM:

- [ ] Install Docker and Docker Compose plugin (no build toolchains beyond what Docker needs).
- [ ] Add your user to the `docker` group (or ensure the deploy user can run `sudo docker compose`).

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

## 3. Deploy from artifacts

- [ ] Copy to VM: `docker-compose.gcp.yaml` (from repo `deployment/docker-compose.gcp.yaml`) and `.env`.
- [ ] Set `IMAGE_TAG=<sha>` in `.env` to the known-good tag (or let the deploy workflow set it).
- [ ] Run: `sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d` (frontend, backend, worker, Redis, Mongo, Qdrant).
- [ ] Wait for services to show healthy: `sudo docker compose -f docker-compose.gcp.yaml ps`.

## 4. Acceptance checks

- [ ] `curl -sf http://localhost:7091/api/health` returns 200.
- [ ] `curl -sf http://localhost:7091/api/ready` returns 200 and `"status":"ready"`.
- [ ] Run `./scripts/smoke_check.sh http://localhost:7091` from repo (or equivalent on VM if you copy the script).
- [ ] Backend and worker logs show no ERRORs: `sudo docker compose -f docker-compose.gcp.yaml logs backend worker --tail 50`.
- [ ] Frontend loads (http://VM_IP or your domain on port 80). API at VM:7091 or assistant-api.mannyroy.com.
- [ ] Optional: create a test source, run a query, confirm vector store and LLM path work.

## 5. Cutover and rollback

- [ ] Point DNS or load balancer to the VM (frontend and API as needed).
- [ ] Monitor for one business cycle (or 24h).
- [ ] Keep previous image tags documented for rollback: set `IMAGE_TAG=<previous-sha>` and `up -d` if needed.

## 6. Decommission old VM

- [ ] Only after acceptance and monitoring: snapshot old VM if desired, then stop/delete it.
- [ ] Remove old VM from DNS/firewall and clean up any static IPs if not reused.

## Quick reference

| Step        | Command (on VM, from deploy dir) |
|------------|-----------------------------------|
| Start      | `sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d` |
| Status     | `sudo docker compose -f docker-compose.gcp.yaml ps` |
| Frontend   | Port 80 (nginx in container) |
| Backend logs | `sudo docker compose -f docker-compose.gcp.yaml logs -f backend` |
| Worker logs  | `sudo docker compose -f docker-compose.gcp.yaml logs -f worker` |
| Cloud Logging | **Logging → Logs Explorer** in GCP Console (resource: GCE VM instance). See [CLOUD-LOGGING-SETUP.md](CLOUD-LOGGING-SETUP.md). |
| Stop       | `sudo docker compose -f docker-compose.gcp.yaml down` |

For debugging, see [DEBUGGING-RUNBOOK.md](DEBUGGING-RUNBOOK.md). To rotate app secrets, update the secret in Secret Manager and redeploy (or run the fetch script on the VM); see [SECRET-MANAGER-SETUP.md](SECRET-MANAGER-SETUP.md).

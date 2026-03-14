# Plan 2.0: Fresh VM deployment checklist

Use this checklist when provisioning a new 30GB VM for the **backend** stack. The **frontend** is deployed to **Cloud Run** by the GitHub Actions workflow; see [CLOUD-RUN-SETUP.md](CLOUD-RUN-SETUP.md). Do **not** build backend/worker on the VM; use CI-built images only.

## Continue deployment (after Cloud Run IAM is done)

1. **GitHub secrets** – In the repo: **Settings → Secrets and variables → Actions**. Ensure you have: `GCP_SA_KEY` (JSON for github-actions-sa), `VM_IP`, `VM_USER`, `SSH_PRIVATE_KEY`. Optional: `VITE_API_HOST`, `VITE_BASE_URL`.
2. **VM ready** – VM exists, Docker + Compose installed, `/opt/docsgpt` has `.env` and `docker-compose.gcp.yaml` (backend-only from repo). The user that `VM_USER` logs in as can run `docker compose` (e.g. in `docker` group). VM can pull from Artifact Registry (same project default SA, or run `gcloud auth configure-docker northamerica-northeast1-docker.pkg.dev` on the VM).
3. **Trigger deploy** – Push to `main` or go to **Actions → Deploy to GCP (Cloud Run + VM) → Run workflow**. The workflow will build both images, deploy frontend to Cloud Run, then SSH to the VM and run `compose pull` / `up -d`.
4. **Validate** – Open the Cloud Run URL (from the workflow log or Cloud Console), hit the API (VM IP:7091 or assistant-api.mannyroy.com), run the acceptance checks below.

## Pre-requisites

- [ ] Preflight CI has passed.
- [ ] Backend image is in Artifact Registry (workflow or `./scripts/push-backend-to-gcp.sh`). Frontend is deployed to Cloud Run by the workflow.
- [ ] `.env` and VM-only Compose file (`docker-compose.gcp.yaml`) are ready to copy to the VM.

## 1. Provision VM

- [ ] Create a new Compute Engine VM with **30GB boot disk** (e.g. `--boot-disk-size=30GB` if using gcloud; `gcp-setup.sh` uses 30GB by default).
- [ ] Open firewall for API (e.g. 7091 or 80/443 if nginx/TLS in front). Frontend is on Cloud Run, so VM does not serve the UI.
- [ ] SSH access configured (e.g. `gcloud compute ssh <instance> --zone=...`).

## 2. Install runtime only

On the VM:

- [ ] Install Docker and Docker Compose plugin (no build toolchains beyond what Docker needs).
- [ ] Add your user to the `docker` group and start a new session.

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

## 3. Deploy from artifacts

- [ ] Copy to VM: `docker-compose.gcp.yaml` (or your production Compose file) and `.env`.
- [ ] Set `IMAGE_TAG=<sha>` in `.env` to the known-good backend tag (or let the deploy workflow set it).
- [ ] Run: `docker compose -f docker-compose.gcp.yaml --env-file .env up -d` (backend, worker, Redis, Mongo, Qdrant only).
- [ ] Wait for services to show `healthy`: `docker compose -f docker-compose.gcp.yaml ps`.

## 4. Acceptance checks

- [ ] `curl -sf http://localhost:7091/api/health` returns 200.
- [ ] `curl -sf http://localhost:7091/api/ready` returns 200 and `"status":"ready"`.
- [ ] Run `./scripts/smoke_check.sh http://localhost:7091` from repo (or equivalent on VM if you copy the script).
- [ ] Backend and worker logs show no ERRORs: `docker compose logs backend worker --tail 50`.
- [ ] Frontend loads from Cloud Run URL (or custom domain). API at VM or assistant-api.mannyroy.com.
- [ ] Optional: create a test source, run a query, confirm vector store and LLM path work.

## 5. Cutover and rollback

- [ ] Point DNS or load balancer to the new VM.
- [ ] Monitor for one business cycle (or 24h).
- [ ] Keep previous image tags documented for rollback: redeploy with those tags if needed.

## 6. Decommission old VM

- [ ] Only after acceptance and monitoring: snapshot old VM if desired, then stop/delete it.
- [ ] Remove old VM from DNS/firewall and clean up any static IPs if not reused.

## Quick reference

| Step        | Command (on VM, from deploy dir) |
|------------|-----------------------------------|
| Start      | `docker compose -f docker-compose.gcp.yaml --env-file .env up -d` |
| Status     | `docker compose -f docker-compose.gcp.yaml ps` |
| Backend logs | `docker compose -f docker-compose.gcp.yaml logs -f backend` |
| Worker logs  | `docker compose -f docker-compose.gcp.yaml logs -f worker` |
| Stop       | `docker compose -f docker-compose.gcp.yaml down` |

For debugging, see [DEBUGGING-RUNBOOK.md](DEBUGGING-RUNBOOK.md).

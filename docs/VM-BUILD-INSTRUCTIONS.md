# DocsGPT: VM deploy (artifact-based, Plan 2.0)

The **VM runs the full stack** (frontend on port 80, backend on 7091, worker, Redis, Mongo, Qdrant). Use CI-built images from Artifact Registry; do not build backend or frontend on the VM. See [GH-ACTIONS-DEPLOY.md](GH-ACTIONS-DEPLOY.md) and [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md) for the GitHub Actions workflow and checklist.

## 1) Provision a fresh VM

- Create a new Compute Engine VM with a **50GB boot disk** (default in `gcp-setup.sh`; avoids "No space left on device" during pulls and container storage).
- Open firewall for **frontend (80)** and **API (7091)** (or 80/443 if you put nginx/TLS in front).
- Install only runtime tools:

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Start a new shell session after adding your user to the Docker group.

## 2) Copy deployment files and environment

From your local repo:

```bash
gcloud compute scp deployment/docker-compose.gcp.yaml docsgpt-prod:/opt/docsgpt/ --zone=northamerica-northeast1-a
gcloud compute scp .env docsgpt-prod:/opt/docsgpt/ --zone=northamerica-northeast1-a
```

On VM:

```bash
cd /opt/docsgpt
ls -la .env docker-compose.gcp.yaml
```

Ensure `.env` includes `IMAGE_TAG=<sha>` (or the workflow will set it on deploy). The compose file uses `IMAGE_TAG` for both frontend and backend images.

## 3) Build and push images (CI or local)

**Preferred:** Use the **GitHub Actions** workflow (push to `main` or **Actions → Deploy to GCP (VM) → Run workflow**). It builds backend and frontend for `linux/amd64`, pushes to Artifact Registry, then SSHs to the VM and runs `sudo docker compose pull` and `up -d`.

**Manual build/push:** From your Mac, after preflight passes:

```bash
gcloud auth configure-docker ${ARTIFACT_REGION:-northamerica-northeast1}-docker.pkg.dev

# Backend (linux/amd64)
./scripts/push-backend-to-gcp.sh "sha-$(git rev-parse --short HEAD)"

# Frontend: build and push with same tag
docker buildx build --platform linux/amd64 \
  -f frontend/Dockerfile.production \
  --build-arg VITE_API_HOST="${VITE_API_HOST:-https://assistant-api.mannyroy.com}" \
  --build-arg VITE_BASE_URL="${VITE_BASE_URL:-https://assistant.mannyroy.com}" \
  -t northamerica-northeast1-docker.pkg.dev/manny-roy-consulting/docsgpt-repo/frontend:$(git rev-parse HEAD) \
  --push frontend
```

Set `IMAGE_TAG` in `.env` on the VM to the same tag (e.g. commit SHA) before starting the stack.

## 4) Start stack and validate health

On the VM:

```bash
cd /opt/docsgpt
sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d
sudo docker compose -f docker-compose.gcp.yaml ps
```

Validate:

```bash
curl -sf http://localhost:7091/api/health
curl -sf http://localhost:7091/api/ready
curl -sf -o /dev/null -w "%{http_code}" http://localhost:80
sudo docker compose -f docker-compose.gcp.yaml logs backend worker --tail 50
```

Frontend at http://VM_IP (port 80); API at http://VM_IP:7091.

## 5) Cutover and rollback

1. Point DNS or load balancer to the VM (frontend and API as needed).
2. Run a short smoke checklist: API healthy, worker online, frontend loads, ingestion and vector search work.
3. Rollback: set `IMAGE_TAG=<previous-sha>` in `.env` and run `sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d`.

## 6) Decommission old VM

Only after acceptance checks pass: snapshot (optional), stop old VM, monitor new VM, then delete old VM resources.

## Quick reference

| Action | Command (on VM, from /opt/docsgpt) |
|--------|-------------------------------------|
| Start stack | `sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d` |
| Show status | `sudo docker compose -f docker-compose.gcp.yaml ps` |
| Backend logs | `sudo docker compose -f docker-compose.gcp.yaml logs -f backend` |
| Worker logs | `sudo docker compose -f docker-compose.gcp.yaml logs -f worker` |
| Frontend | Port 80 (nginx in container) |
| Stop stack | `sudo docker compose -f docker-compose.gcp.yaml down` |

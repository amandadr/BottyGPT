# DocsGPT: VM deploy (artifact-based, Plan 2.0)

The **VM runs only the backend stack** (backend, worker, Redis, Mongo, Qdrant). The **frontend is hosted on Cloud Run**; see [CLOUD-RUN-SETUP.md](CLOUD-RUN-SETUP.md) and [GH-ACTIONS-DEPLOY.md](GH-ACTIONS-DEPLOY.md). This guide avoids in-VM source builds: use CI-built images. For a full checklist, see **[DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)**.

## 1) Provision a fresh VM

- Create a new Compute Engine VM with a **30GB boot disk** (default in `gcp-setup.sh`; avoids "No space left on device" during pulls and container storage).
- Open firewall for API access (e.g. `7091` if exposing the API directly, or `80`/`443` if you put nginx/TLS in front of the VM). Frontend is on Cloud Run, so the VM does not need to serve port 80 for the UI.
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

## 3) Build and push images (from your Mac)

After preflight passes locally, build and push the backend to your Artifact Registry so the VM only pulls (no build on VM). The script builds for **linux/amd64** so the image runs on GCP Compute Engine without exec-format or arch mismatch (e.g. when building on Apple Silicon):

```bash
# One-time: authenticate Docker to the registry
gcloud auth configure-docker ${ARTIFACT_REGION:-northamerica-northeast1}-docker.pkg.dev

# One-time on Apple Silicon: ensure buildx can target amd64 (Docker Desktop usually has this)
docker buildx ls

# Push backend for amd64 with an immutable tag (recommended)
./scripts/push-backend-to-gcp.sh "sha-$(git rev-parse --short HEAD)"
# Or push as latest: ./scripts/push-backend-to-gcp.sh
```

Override `GCP_PROJECT`, `ARTIFACT_REGION`, or `REPO_NAME` if needed. To build for a different platform, set `PLATFORM` (e.g. `PLATFORM=linux/arm64`). Frontend: build from `frontend/` with `--platform linux/amd64` and push to the same registry.

If the push is slow or was canceled: run `./scripts/docker-inspect-and-clean.sh` to free space (keeps build cache), then run the push script again; the build will use cache and only the push will run. If upload from your Mac is too slow, build and push from CI (e.g. GitHub Actions) to your Artifact Registry instead.

Update `deployment/docker-compose.gcp.yaml` (or the copy on the VM) so the backend image tag matches what you pushed (e.g. `backend:sha-abc1234`).

## 4) Start stack and validate health

```bash
cd /opt/docsgpt
docker compose -f docker-compose.gcp.yaml --env-file .env up -d
docker compose -f docker-compose.gcp.yaml ps
```

Validate:

```bash
curl --fail http://localhost:7091/api/health
curl --fail http://localhost:7091/api/ready
docker compose -f docker-compose.gcp.yaml logs backend --since 5m
docker compose -f docker-compose.gcp.yaml logs worker --since 5m
```

## 5) Cutover and rollback

1. Point DNS/load balancer to the new VM.
2. Run a short smoke checklist:
   - API responses healthy
   - worker online
   - source ingestion works
   - vector search works
3. Keep previous artifact tags available for rollback:

```bash
docker compose -f docker-compose.gcp.yaml --env-file .env pull
docker compose -f docker-compose.gcp.yaml --env-file .env up -d
```

If rollback is needed, set compose image tags back to the prior known-good pair and restart.

## 6) Decommission old VM

Only after acceptance checks pass:

- snapshot (optional),
- stop old VM,
- monitor new VM for at least one business cycle,
- delete old VM resources.

## Quick reference

| Action | Command |
|--------|---------|
| Start stack | `docker compose -f docker-compose.gcp.yaml --env-file .env up -d` |
| Show status | `docker compose -f docker-compose.gcp.yaml ps` |
| Backend logs | `docker compose -f docker-compose.gcp.yaml logs -f backend` |
| Worker logs | `docker compose -f docker-compose.gcp.yaml logs -f worker` |
| Stop stack | `docker compose -f docker-compose.gcp.yaml down` |

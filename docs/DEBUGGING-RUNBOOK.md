# First 10 minutes of debugging (Plan 2.0)

Use this runbook when the stack is unhealthy or you need to find a failing dependency quickly. The stack includes **frontend** (port 80), **backend** (7091), **worker**, Redis, Mongo, and Qdrant. On the VM, use **`sudo docker compose`** (or run as a user in the `docker` group).

**Production:** App secrets are managed via [Secret Manager](SECRET-MANAGER-SETUP.md) (when `USE_SECRET_MANAGER=true`). Container logs are sent to [Cloud Logging](CLOUD-LOGGING-SETUP.md) via the Ops Agent—use **Logging → Logs Explorer** in GCP Console to search by severity, service, or message.

## 1. Check container health (0–2 min)

From the host where Compose runs (on VM use `sudo`):

```bash
sudo docker compose -f deployment/docker-compose.gcp.yaml ps
```

Look for `unhealthy` or `restarting`. Note which service is failing (frontend, backend, worker, redis, mongo, qdrant).

## 2. Hit readiness and health endpoints (1 min)

If the backend port is exposed (default 7091):

```bash
curl -s http://localhost:7091/api/health
curl -s http://localhost:7091/api/ready
```

If the frontend does not load, check that the frontend container is running and port 80 is open: `curl -s -o /dev/null -w "%{http_code}" http://localhost:80`.

- `api/health`: liveness; expect `{"status":"ok","service":"backend"}`.
- `api/ready`: dependency checks; expect `{"status":"ready","checks":{...}}`. If `"status":"degraded"`, inspect `checks` for which service failed (redis, mongo, qdrant).

## 3. Run healthcheck inside backend or worker (1 min)

From host (on VM use `sudo`):

```bash
sudo docker compose -f deployment/docker-compose.gcp.yaml exec backend python -m application.healthcheck --target dependencies
sudo docker compose -f deployment/docker-compose.gcp.yaml exec worker python -m application.healthcheck --target worker
```

Exit code 0 means all dependency checks passed. Non-zero or JSON with `"healthy": false` indicates which service failed.

## 4. Inspect structured logs (2–3 min)

Backend and worker emit JSON lines (timestamp, severity, level, service, request_id, message). Use `request_id` to trace a single request.

**On the VM:**

```bash
sudo docker compose -f deployment/docker-compose.gcp.yaml logs --tail 100 backend
sudo docker compose -f deployment/docker-compose.gcp.yaml logs --tail 100 worker
```

**In Cloud Logging (production):** Open **Logging → Logs Explorer**, select resource type **GCE VM instance** and your instance. Filter by `jsonPayload.log=~"ERROR"` or `jsonPayload.severity="ERROR"` to find errors. Use `jsonPayload.service` to distinguish backend vs worker.

Search for `"level":"ERROR"` or `"exception"` in either place. Confirm `service` (e.g. `docsgpt-backend` vs `docsgpt-worker`) and timestamps.

## 5. Confirm environment and connectivity (2 min)

On the VM, ensure `.env` is present and key values are set (no secrets in logs):

- `VECTOR_STORE=qdrant`
- `QDRANT_URL` (e.g. `http://qdrant:6333` when using Compose service name)
- `MONGO_URI`, `CELERY_BROKER_URL`, `CACHE_REDIS_URL` pointing at the correct hosts (e.g. `redis`, `mongo` in Compose).

Optional: run the standalone Qdrant script from repo root (with `.env`):

```bash
python scripts/test_qdrant_connection.py
```

## 6. Debugging "Add source" / remote upload errors

If adding a source fails with **"Unknown arguments: ['init_from']"** (or similar):

**Cause:** The error is raised by the **Qdrant client** (vector store), not by the crawler or API. Document metadata is passed into the vector store; if it contains unknown keys (e.g. `init_from`), the Qdrant client rejects them.

1. **Backend logs** (Compose or Cloud Logging): Look for:
   - `Remote upload: source_type=... config_keys=[...]` — what the API received.
   - `Remote upload: calling ingest_remote loader=...` — what is sent to the Celery task.

2. **Worker logs**: Look for:
   - `remote_worker: loader=... source_data type=...` — payload shape.
   - `Error in remote_worker task: loader=... error=...` — failure and source_data shape.

3. **Fix (code):** The embedding pipeline sanitizes document metadata before calling the vector store: only `source_id`, `source`, `file_path`, `title`, `key` are passed. Ensure you’re on a version that includes this and that no code path adds extra keys to doc metadata before `embed_and_store_documents`.

4. **Frontend**: DevTools → Console shows `[Upload] Add source failed:` with status and message. The UI shows the backend error when the API returns `error` or `message` in the JSON body.

## 7. Common failure patterns

| Symptom | Likely cause | Action |
|--------|---------------|--------|
| Backend `unhealthy` | Redis/Mongo/Qdrant down or unreachable | Check infra healthchecks; ensure `depends_on` conditions are met; check firewall/network. |
| Worker restarts repeatedly | Cannot reach Redis or backend API | Verify `CELERY_BROKER_URL`, `API_URL`; ensure backend is healthy first. |
| `api/ready` returns 503 | One of redis/mongo/qdrant failed | Use `api/ready` JSON to see which check failed; fix that service or its URL. |
| Permission errors on indexes/inputs/vectors | Volume owned by root, container runs as non-root | Use `user: "0"` for backend/worker in Compose if required, or pre-create volumes with correct ownership. |

## 8. Rotating secrets (Secret Manager)

If **USE_SECRET_MANAGER** is enabled, app secrets live in GCP Secret Manager (`docsgpt-env`). To rotate: add a new version of the secret in **Secret Manager** in the console (or `gcloud secrets versions add docsgpt-env --data-file=- < .env`). The next deploy will use the new version. To apply without a code deploy, on the VM run: `gcloud secrets versions access latest --secret=docsgpt-env --project=manny-roy-consulting > /opt/docsgpt/.env` then restart the stack. See [SECRET-MANAGER-SETUP.md](SECRET-MANAGER-SETUP.md).

## 9. Escalation

- If dependency checks pass but requests fail: inspect application logs and `request_id` for that request.
- **If the VM is out of disk** ("no space left on device" during `docker pull` or container start): The backend image includes PyTorch (~2GB+), so old images and layers can fill a 50GB disk. Free space by running on the VM:
  ```bash
  sudo docker system prune -af && sudo docker image prune -a -f && sudo docker builder prune -af
  sudo journalctl --vacuum-time=3d
  ```
  Then retry `sudo docker compose pull` and `up -d`. See **scripts/vm-free-disk-space.sh** for a full cleanup script. Use a **50GB boot disk** (default in `gcp-setup.sh`) to reduce how often this happens. To resize an existing GCP VM disk, see [Resize a persistent disk](https://cloud.google.com/compute/docs/disks/resize-persistent-disk) (resize in GCP, then on the VM run `sudo growpart /dev/sda 1` and `sudo resize2fs /dev/sda1`).
- For TLS/domain issues: see [TLS-SETUP.md](TLS-SETUP.md).
- For log-based metrics or alerting in Cloud Logging: see [CLOUD-LOGGING-SETUP.md](CLOUD-LOGGING-SETUP.md#6-log-based-metrics-and-alerting-optional).

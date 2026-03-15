# First 10 minutes of debugging (Plan 2.0)

Use this runbook when the stack is unhealthy or you need to find a failing dependency quickly. The stack includes **frontend** (port 80), **backend** (7091), **worker**, Redis, Mongo, and Qdrant. On the VM, use **`sudo docker compose`** (or run as a user in the `docker` group).

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

Backend and worker emit JSON lines (timestamp, level, service, request_id, message). Use `request_id` to trace a single request.

```bash
sudo docker compose -f deployment/docker-compose.gcp.yaml logs --tail 100 backend
sudo docker compose -f deployment/docker-compose.gcp.yaml logs --tail 100 worker
```

Search for `"level":"ERROR"` or `"exception"`. Confirm `service` (e.g. `docsgpt-backend` vs `docsgpt-worker`) and timestamps.

## 5. Confirm environment and connectivity (2 min)

On the VM, ensure `.env` is present and key values are set (no secrets in logs):

- `VECTOR_STORE=qdrant`
- `QDRANT_URL` (e.g. `http://qdrant:6333` when using Compose service name)
- `MONGO_URI`, `CELERY_BROKER_URL`, `CACHE_REDIS_URL` pointing at the correct hosts (e.g. `redis`, `mongo` in Compose).

Optional: run the standalone Qdrant script from repo root (with `.env`):

```bash
python scripts/test_qdrant_connection.py
```

## 6. Common failure patterns

| Symptom | Likely cause | Action |
|--------|---------------|--------|
| Backend `unhealthy` | Redis/Mongo/Qdrant down or unreachable | Check infra healthchecks; ensure `depends_on` conditions are met; check firewall/network. |
| Worker restarts repeatedly | Cannot reach Redis or backend API | Verify `CELERY_BROKER_URL`, `API_URL`; ensure backend is healthy first. |
| `api/ready` returns 503 | One of redis/mongo/qdrant failed | Use `api/ready` JSON to see which check failed; fix that service or its URL. |
| Permission errors on indexes/inputs/vectors | Volume owned by root, container runs as non-root | Use `user: "0"` for backend/worker in Compose if required, or pre-create volumes with correct ownership. |

## 7. Escalation

- If dependency checks pass but requests fail: inspect application logs and `request_id` for that request.
- If the VM is out of disk: run `docker system prune -a -f` only if you can afford to re-pull images; prefer cleaning logs and old volumes first. To avoid "No space left on device" during pip install or pulls, use a **50GB boot disk** (default in `gcp-setup.sh`). To resize an existing GCP VM disk, see [Resize a persistent disk](https://cloud.google.com/compute/docs/disks/resize-persistent-disk) (resize in GCP, then on the VM run `sudo growpart /dev/sda 1` and `sudo resize2fs /dev/sda1` for the root partition).
- For TLS/domain issues: see [TLS-SETUP.md](TLS-SETUP.md).

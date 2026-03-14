# Testing approach

Plan 2.0 makes connectivity and dependency validation mandatory in CI/CD before deployment artifacts are promoted.

## Mandatory preflight gates

Every PR and `main` push must pass `.github/workflows/preflight.yml`:

1. **Dependency graph check**
   - Install `application/requirements.txt` and `tests/requirements.txt`
   - Run `pip check`
2. **Backend smoke tests**
   - Run targeted backend tests (`tests/test_app.py`, `tests/test_celery.py`)
3. **Image-size guardrail**
   - Build backend image from `application/Dockerfile`
   - Fail if image exceeds `MAX_BACKEND_IMAGE_BYTES`
4. **Compose connectivity smoke test**
   - Start `deployment/docker-compose.preflight.yaml`
   - Verify:
     - `GET /api/health`
     - `GET /api/ready`
     - `python -m application.healthcheck --target dependencies` from backend container

If any gate fails, the deployment pipeline must stop.

## Runtime diagnostics

The backend now exposes:

- `GET /api/health` for liveness
- `GET /api/ready` for dependency readiness (`redis`, `mongo`, and `qdrant` when enabled)

The shared healthcheck helper is:

- `python -m application.healthcheck --target dependencies`
- `python -m application.healthcheck --target backend`
- `python -m application.healthcheck --target worker`

## Local verification (before pushing)

```bash
python -m pip install -r application/requirements.txt
python -m pip install -r tests/requirements.txt
pip check
python -m pytest tests/test_app.py tests/test_celery.py -q
docker compose -f deployment/docker-compose.preflight.yaml up -d --build --wait
./scripts/smoke_check.sh
docker compose -f deployment/docker-compose.preflight.yaml down -v --remove-orphans
```

After preflight is healthy, run `./scripts/smoke_check.sh` (optional: pass base URL). Then tear down so the next run is clean.

## Operational debugging

See **[DEBUGGING-RUNBOOK.md](DEBUGGING-RUNBOOK.md)** for a step-by-step "first 10 minutes" runbook.

- **Post-deploy smoke:** run `./scripts/smoke_check.sh [BASE_URL]` (default `http://localhost:7091`) to verify health and readiness.
- Use structured logs and request IDs: check container health, `/api/ready`, then `python -m application.healthcheck --target dependencies` inside backend/worker, and `.env` for `MONGO_URI`, `CELERY_BROKER_URL`, `CACHE_REDIS_URL`, `QDRANT_URL`.

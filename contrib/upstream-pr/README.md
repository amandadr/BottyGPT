# Upstream PR: Health and readiness endpoints + healthcheck CLI

This folder contains the exact files and edits to open a PR to [arc53/DocsGPT](https://github.com/arc53/DocsGPT) adding:

- `**GET /api/health**` – liveness (backend process up)
- `**GET /api/ready**` – readiness (Redis, Mongo, and Qdrant when enabled)
- `**application/healthcheck.py**` – CLI for Docker/Kubernetes healthchecks
- `**application/core/service_checks.py**` – dependency check helpers (minimal; no startup logic)

## How to open the PR

1. **Fork and clone upstream**
  ```bash
   git clone https://github.com/arc53/DocsGPT.git docsgpt-upstream-pr
   cd docsgpt-upstream-pr
   git checkout -b feat/health-and-ready-endpoints
  ```
2. **Add new files**
  - Copy `contrib/upstream-pr/application/core/service_checks.py` → `application/core/service_checks.py`
  - Copy `contrib/upstream-pr/application/healthcheck.py` → `application/healthcheck.py`
3. **Edit `application/app.py`**
  - Follow the steps in [APP_PATCH.md](APP_PATCH.md): add the import and the two routes (`/api/health`, `/api/ready`) before `@app.route("/api/generate_token")`.
4. **Copy unit tests**
  - Copy `contrib/upstream-pr/tests/test_health.py` into the upstream fork’s `tests/` directory.
5. **Run checks**
  ```bash
   pip install -r application/requirements.txt -r tests/requirements.txt
   ruff check application/ tests/
   ruff format application/ tests/
   python -m pytest tests/test_health.py tests/test_app.py -v
  ```
6. **Commit and push**
  ```bash
   git add application/core/service_checks.py application/healthcheck.py application/app.py tests/test_health.py
   git commit -m "Add /api/health, /api/ready and healthcheck CLI for orchestration"
   git push origin feat/health-and-ready-endpoints
  ```
7. **Open the PR** on GitHub against `arc53/DocsGPT` `main` and use the description below.

---

## PR description (copy-paste)

**Title:** Add `/api/health`, `/api/ready` and healthcheck CLI for orchestration

**Description:**

### What

- `**GET /api/health`** – Liveness endpoint: returns `200` and `{"status": "ok", "service": "backend"}`. For Kubernetes liveness probes and Docker HEALTHCHECK.
- `**GET /api/ready**` – Readiness endpoint: checks Redis, Mongo, and (when vector store is Qdrant) Qdrant. Returns `200` with `{"status": "ready", "checks": {...}}` when all are up, and `503` with `{"status": "degraded", "checks": {...}}` when any dependency is down.
- `**application/healthcheck.py**` – CLI for container healthchecks:
  - `python -m application.healthcheck --target dependencies` – runs the same checks as `/api/ready` and exits 0/1.
  - `python -m application.healthcheck --target backend --url http://localhost:7091/api/health` – checks the backend HTTP endpoint.
  - `--target worker` is supported (same as dependencies today) for future use.
- `**application/core/service_checks.py**` – New module with `required_service_checks()` and `summarize_checks()` used by `/api/ready` and the healthcheck CLI. No new settings; uses existing `CELERY_BROKER_URL`, `MONGO_URI`, `VECTOR_STORE`, `QDRANT_URL`, `QDRANT_API_KEY`.

### Why

- Orchestrators (Kubernetes, Docker Compose, ECS, etc.) need liveness and readiness endpoints to know when to send traffic and when to restart the process.
- The healthcheck CLI allows using the same logic inside containers without HTTP (e.g. `HEALTHCHECK CMD python -m application.healthcheck --target dependencies`).

### Behaviour

- `/api/health` and `/api/ready` are callable without authentication (upstream’s `before_request` does not return 401 when no token is present).
- When `VECTOR_STORE` is not `qdrant`, only Redis and Mongo are checked for readiness.

### Tests

- `tests/test_health.py` – unit tests for `/api/health`, `/api/ready` (with mocked dependency checks), and for the healthcheck CLI (`--target dependencies` and `--target backend`).

### Checklist

- New files: `application/core/service_checks.py`, `application/healthcheck.py`
- Changes to `application/app.py`: import + two routes only
- Unit tests added; `pytest tests/test_health.py` passes
- `ruff check` and `ruff format` run on changed files


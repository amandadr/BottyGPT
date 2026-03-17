# Contribution plan: Health and readiness for upstream DocsGPT

This document plans the contribution of **`/api/health`**, **`/api/ready`**, and **`application/healthcheck.py`** (plus the required **`application/core/service_checks.py`**) to [arc53/DocsGPT](https://github.com/arc53/DocsGPT).

---

## 1. Scope (what to contribute)

| Item | Upstream today | Contribution |
|------|-----------------|--------------|
| `GET /api/health` | Not present | Add liveness endpoint: `{"status": "ok", "service": "backend"}` |
| `GET /api/ready` | Not present | Add readiness endpoint: dependency checks (Redis, Mongo, Qdrant if enabled), 200 when ready, 503 when degraded |
| `application/healthcheck.py` | 404 (does not exist) | New file: CLI for Docker/Kubernetes healthchecks (`--target dependencies \| worker \| backend`) |
| `application/core/service_checks.py` | 404 (does not exist) | New file: `required_service_checks()`, `summarize_checks()`, and check helpers |

**Out of scope for this PR (optional follow-ups):**

- Startup diagnostics and strict startup dependency checks (`log_startup_diagnostics`, `run_startup_dependency_checks`, `STARTUP_DEPENDENCY_CHECKS`, `STARTUP_CHECK_STRICT`) — can be a separate PR.
- Documentation guide (“Verifying your deployment”) — recommend a second PR after this one is merged.

---

## 2. Dependencies

- **`/api/ready`** and **`healthcheck.py`** both depend on:
  - `application.core.service_checks.required_service_checks`
  - `application.core.service_checks.summarize_checks`
- **`service_checks.py`** uses existing upstream settings: `CELERY_BROKER_URL`, `MONGO_URI`, `VECTOR_STORE`, `QDRANT_URL`, `QDRANT_API_KEY` (all already in upstream `application/core/settings.py`).
- **Auth:** Upstream’s `before_request` does not return 401 when no token is present (`decoded_token = None`), so `/api/health` and `/api/ready` will be callable without authentication. No auth exemption needed unless upstream adds stricter behavior later.

---

## 3. Files to add or change

### 3.1 New file: `application/core/service_checks.py`

**Include (minimal set for health/ready + healthcheck CLI):**

- `CheckResult` dataclass
- `_check_redis(url)` → CheckResult
- `_check_mongo(uri)` → CheckResult  
- `_check_qdrant(url)` → CheckResult (uses `settings.QDRANT_API_KEY`, `timeout=2.0`)
- `_is_qdrant_enabled()` → bool (`settings.VECTOR_STORE.lower() == "qdrant"`)
- `_normalize_host(value)` → str (for display; use `urlparse`)
- `required_service_checks()` → Dict[str, CheckResult] (Redis, Mongo, and Qdrant only when enabled)
- `summarize_checks(checks)` → Tuple[bool, Dict[str, dict]]

**Omit in this PR (optional later):**

- `log_startup_diagnostics`
- `run_startup_dependency_checks`
- Any use of `STARTUP_DEPENDENCY_CHECKS` / `STARTUP_CHECK_STRICT`

**Dependencies:** `redis`, `pymongo`, `qdrant_client`, `application.core.settings` (all already in upstream).

---

### 3.2 New file: `application/healthcheck.py`

Contribute **as-is** from your fork. It only uses:

- `required_service_checks`, `summarize_checks` from `application.core.service_checks`
- Standard library: `argparse`, `json`, `sys`, `urllib.error`, `urllib.request`

No changes needed for upstream.

---

### 3.3 Modify: `application/app.py`

**Add:**

1. **Import** (after other `application.core` imports):

   ```python
   from application.core.service_checks import required_service_checks, summarize_checks
   ```

2. **Two routes** (before `@app.route("/api/generate_token")` so they stay with other “system” endpoints):

   ```python
   @app.route("/api/health")
   def healthcheck():
       return jsonify({"status": "ok", "service": "backend"})

   @app.route("/api/ready")
   def readiness_check():
       checks = required_service_checks()
       all_ok, payload = summarize_checks(checks)
       status_code = 200 if all_ok else 503
       return jsonify({"status": "ready" if all_ok else "degraded", "checks": payload}), status_code
   ```

**Do not change:** Upstream’s `before_request`, `after_request`, or any logging/request_id logic. Match upstream’s indentation and style (e.g. 1-space indent if that’s what they use).

---

## 4. Tests

- **Unit tests (recommended):**
  - In `tests/test_app.py` or a new `tests/test_health.py`:
    - `GET /api/health` returns 200 and `{"status": "ok", "service": "backend"}`.
    - `GET /api/ready` returns 200 when dependencies are OK and JSON with `"status": "ready"` and `"checks"`; when a dependency is down (or mocked failed), returns 503 and `"status": "degraded"`.
  - For `application/healthcheck.py`: test `main()` with `--target backend` (and optionally `--target dependencies` with mocked `required_service_checks`/`summarize_checks`) and assert exit code and JSON output.
- **Integration:** Existing `tests/integration/test_misc.py` already tries `/api/health`; it will start passing once the endpoint exists. Optionally add a check for `/api/ready` in the same style.

---

## 5. Conventions and checks

- **Python style:** Match upstream (PEP 8, type hints, docstrings). They use `ruff`; run `ruff check application/ tests/` and fix any issues.
- **Imports:** Use the same order and style as upstream `app.py` (stdlib, third-party, then `application.*`).
- **Docstrings:** Add short docstrings for the new public functions in `service_checks.py` and for the two new routes in `app.py` (Google style if that’s what the project uses).

---

## 6. PR workflow

1. **Fork and branch**
   - Fork [arc53/DocsGPT](https://github.com/arc53/DocsGPT) (if not already).
   - Create a branch from `main`, e.g. `feat/health-and-ready-endpoints`.

2. **Apply changes**
   - Add `application/core/service_checks.py` (minimal version above).
   - Add `application/healthcheck.py` (copy from your fork).
   - Edit `application/app.py`: add import and the two routes.

3. **Tests and lint**
   - `python -m pytest tests/test_app.py tests/test_health.py -v` (once tests exist).
   - `ruff check application/ tests/` and `ruff format application/ tests/`.

4. **Commit and PR**
   - Meaningful commit message, e.g. “Add /api/health, /api/ready and healthcheck CLI for orchestration”.
   - In the PR description:
     - Summarize what was added and why (Kubernetes/Docker healthchecks, readiness for dependencies).
     - List the new files and the changes to `app.py`.
     - Note that `/api/health` and `/api/ready` are intended to be callable without authentication for orchestrators.
     - Link to this plan or a short “Verifying your deployment” doc if you’ve drafted it.

5. **After merge (optional)**
   - Open a second PR adding a short “Verifying your deployment” or “Health checks” guide under Deploying (e.g. in the docs site or Wiki), referencing `/api/health`, `/api/ready`, and `python -m application.healthcheck`.

---

## 7. Summary checklist

- [x] Add `application/core/service_checks.py` (minimal: checks + `required_service_checks` + `summarize_checks` only). → See `contrib/upstream-pr/application/core/service_checks.py`.
- [x] Add `application/healthcheck.py` unchanged from fork. → See `contrib/upstream-pr/application/healthcheck.py`.
- [x] In `application/app.py`: add import and `GET /api/health`, `GET /api/ready`. → See `contrib/upstream-pr/APP_PATCH.md`.
- [x] Add unit tests for `/api/health`, `/api/ready`, and optionally for `healthcheck.py`. → See `tests/test_health.py` and `contrib/upstream-pr/tests/test_health.py`.
- [ ] Run pytest and ruff; fix any failures. (Run locally: `pytest tests/test_health.py`, `ruff check application/ tests/`.)
- [ ] Open PR with clear description and scope limited to health/ready + healthcheck CLI. → See `contrib/upstream-pr/README.md` for steps and PR description.

This keeps the first contribution focused and easy to review; startup diagnostics and docs can follow in separate PRs.

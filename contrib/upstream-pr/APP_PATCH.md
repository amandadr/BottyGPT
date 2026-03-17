# app.py changes for upstream

Apply these edits to `application/app.py` in your fork of arc53/DocsGPT.

## 1. Add import

After the existing `from application.core.settings import settings` line, add:

```python
from application.core.service_checks import required_service_checks, summarize_checks  # noqa: E402
```

(Keep any existing `# noqa: E402` style if upstream uses it.)

## 2. Add two routes

Insert **before** `@app.route("/api/generate_token")`:

```python
@app.route("/api/health")
def healthcheck():
    """Liveness: is the backend process up?"""
    return jsonify({"status": "ok", "service": "backend"})


@app.route("/api/ready")
def readiness_check():
    """Readiness: can the backend reach Redis, Mongo, and (if enabled) Qdrant?"""
    checks = required_service_checks()
    all_ok, payload = summarize_checks(checks)
    status_code = 200 if all_ok else 503
    return jsonify({"status": "ready" if all_ok else "degraded", "checks": payload}), status_code
```

## Summary

- **New import:** `required_service_checks`, `summarize_checks` from `application.core.service_checks`.
- **New routes:** `GET /api/health` (always 200), `GET /api/ready` (200 when dependencies OK, 503 when degraded).
- No auth exemption needed: upstream allows unauthenticated requests (decoded_token = None).

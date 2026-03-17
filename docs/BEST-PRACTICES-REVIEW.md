# Deployment setup: conventional vs best-practice gaps

This is a quick review of the current GCP VM + GitHub Actions setup against common best practices. Most of the setup is conventional; the items below are where it diverges or could be improved.

**Enabled in production:** [Secret Manager](SECRET-MANAGER-SETUP.md) (app secrets in `docsgpt-env`, fetched on deploy when `USE_SECRET_MANAGER=true`) and [Cloud Logging](CLOUD-LOGGING-SETUP.md) (Ops Agent on VM sends Docker container logs to Cloud Logging). For the rationale behind these and other decisions (Canadian region, single VM, TLS, CI/CD), see [ARCHITECTURE-DECISIONS.md](ARCHITECTURE-DECISIONS.md).

---

## What is conventional and good

- **Single VM + Docker Compose** for a small/medium app is a standard pattern. Full stack (frontend, backend, worker, Redis, Mongo, Qdrant) on one host is acceptable when scaling is not the priority.
- **Nginx as TLS reverse proxy** with Let's Encrypt (certbot) and HTTP→HTTPS redirect is a common, well-understood approach.
- **CI/CD**: Build on push to `main`, push images to Artifact Registry, deploy via SSH + `docker compose pull && up -d` is a standard pattern. Immutable image tags (commit SHA) and health checks are good.
- **Firewall**: Using GCP firewall rules and instance tags (e.g. `http-server`) to open 80/443 is correct. Not exposing backend port 7091 publicly when using Nginx (gcp-tls) is good.
- **Logging**: `json-file` driver with size/file limits avoids unbounded disk use.
- **Secrets for build**: `VITE_API_HOST` / `VITE_BASE_URL` in GitHub Actions secrets (not in repo) is correct for frontend build-time config.

---

## Gaps and improvements (optional)

### 1. **GitHub Actions: JSON key in secrets**

- **Current:** `GCP_SA_KEY` is a long-lived service account JSON key stored in GitHub Secrets.
- **Best practice:** Prefer **Workload Identity Federation** (WIF) so GitHub OIDC tokens are exchanged for short-lived GCP credentials; no static key to rotate or leak. [Docs](https://github.com/google-github-actions/auth#usage-with-workload-identity-federation). The repo already mentions this in GH-ACTIONS-DEPLOY.md.

### 2. **Secrets on the VM: `.env` file**

- **In use:** **GCP Secret Manager** is enabled: app secrets are stored in `docsgpt-env`, the VM's service account has `roles/secretmanager.secretAccessor`, and with GitHub secret **USE_SECRET_MANAGER** = `true` the deploy workflow fetches the secret into `.env` on each deploy. See [SECRET-MANAGER-SETUP.md](SECRET-MANAGER-SETUP.md).

### 3. **Containers running as root**

- **Current:** Backend and worker use `user: "0"` (root) in Compose, often to match volume ownership.
- **Best practice:** Run as a non-root user inside the container and fix volume ownership (e.g. at build time or via init). Reduces impact of a container breakout. The Dockerfile already has an `appuser`; the override to root is usually for host-mounted volumes.

### 4. **No deploy approval / staging**

- **Current:** Push to `main` triggers a full build and production deploy with no approval or staging environment.
- **Best practice:** For teams, use a **staging** environment (e.g. deploy on push to `develop` or a `staging` branch) and require approval or a separate workflow for production. For a solo/small setup this is often omitted.

### 5. **Internal services published on host ports**

- **Current:** Redis (6379), Mongo (27017), Qdrant (6333) are published on the host (`ports: "6379:6379"` etc.).
- **Best practice:** If only the app stack needs them, use **expose** only (no host port). That keeps them on the Docker network and not reachable from the host network. Publish only when you need direct access (e.g. debugging). GCP firewall can still block these, but reducing surface area is better.

### 6. **TLS: cert renewal and nginx reload**

- **Current:** Cron runs `certbot renew` and then `docker compose exec nginx nginx -s reload`. Manual or script-based.
- **Best practice:** Document that cron runs as root and that the reload is necessary. Optionally use a small **sidecar or host cron** that only reloads nginx when certs actually change (e.g. `certbot renew --deploy-hook "docker compose exec nginx nginx -s reload"`). Current approach is still valid.

### 7. **Project/region hardcoded in workflow**

- **Current:** `PROJECT_ID`, `REGION`, `VM_NAME`, etc. are in the workflow `env`.
- **Best practice:** For reuse across projects, move these to **GitHub variables** or **secrets** (e.g. `GCP_PROJECT_ID`, `GCP_REGION`). Minor; only matters if you clone the repo for another project.

### 8. **Structured production monitoring**

- **In use:** **Cloud Logging** is enabled: the **Ops Agent** runs on the VM with `deployment/ops-agent/config.yaml`, collecting Docker container logs and sending them to Cloud Logging. Backend and worker emit structured JSON with `severity`, `message`, and `service`. View logs in **Logging → Logs Explorer** (resource: GCE VM instance). See [CLOUD-LOGGING-SETUP.md](CLOUD-LOGGING-SETUP.md). Optional: log-based metrics and alerting (e.g. error count, uptime checks on the health endpoint).

---

## Summary

| Area              | Conventional? | Status / suggestion                                      |
|-------------------|---------------|----------------------------------------------------------|
| Architecture      | Yes           | Optional: staging env, approval gate                     |
| TLS / Nginx       | Yes           | Optional: deploy-hook for reload                         |
| CI/CD             | Yes           | Prefer WIF over JSON key; optional env vars               |
| Secrets on VM     | Yes           | **Secret Manager enabled** (docsgpt-env, fetch on deploy) |
| Root in containers| Common        | Optional: non-root + fix volume ownership                 |
| Internal ports    | Acceptable    | Optional: use expose only for Redis/Mongo/Qdrant         |
| Monitoring        | Yes           | **Cloud Logging enabled** (Ops Agent, Docker logs)        |

Overall the setup is **conventional and appropriate** for a single-VM deployment. The items above are incremental improvements you can adopt as the project or team grows.

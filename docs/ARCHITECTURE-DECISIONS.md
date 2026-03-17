# Architecture decisions: why we built it this way

This document records the main architecture and operations decisions made during development of the DocsGPT deployment. It’s written so it can be reused for blog posts or talks: each section stands alone and explains **what we chose**, **why**, and **what we gained**. References to “we” or “I” are intentional so the text can be repurposed into first-person or team narratives.

---

## 1. Canadian region: Montréal (northamerica-northeast1)

**Decision:** Run all production workloads in **Google Cloud’s Montréal region** (`northamerica-northeast1`), with the VM in zone `northamerica-northeast1-a`. Artifact Registry, Compute Engine, Secret Manager, and Cloud Logging are all in this region.

**Why:** We wanted Canadian data residency and low latency for Canadian users and stakeholders. Montréal is a primary Canadian GCP region; keeping compute, storage, and logging in the same region avoids cross-border data flow and keeps operations simple. For a consultancy or product focused on Canadian clients, “data stays in Canada” is a clear benefit for trust and, where relevant, compliance.

**Benefits:**
- Data residency in Canada (compute, container images, secrets, logs).
- Predictable latency for users in Eastern Canada and nearby.
- Single region to reason about for networking, IAM, and billing.
- No need to manage or document data transfer to US or other regions.

**Trade-off:** If most users were in Western Canada or elsewhere, we might add a second region later; for our current scope, one Canadian region was the right fit.

---

## 2. Single VM (Compute Engine) instead of serverless / managed services

**Decision:** Host the full application stack on **one GCP Compute Engine VM** using Docker Compose. We did not use Cloud Run, GKE, or a mix of managed databases and serverless functions for the core app.

**Why:** We needed a predictable cost model, full control over the runtime, and the ability to run the entire stack (frontend, backend API, Celery worker, Redis, MongoDB, Qdrant) in one place without managing multiple cloud products or cross-service networking. A single VM is easy to reason about, backup, and debug. We also tried Cloud Run (and IAP) for the frontend early on; moving the frontend onto the same VM simplified auth, TLS, and deployment and removed the need for IAP and hosted sign-in.

**Benefits:**
- **Cost predictability:** One VM (and its disk) instead of per-request or per-pod billing. We know the monthly ceiling.
- **Operational simplicity:** One host, one SSH target, one `docker compose` to manage. No VPC connectors, private service connections, or multi-region failover to configure.
- **Full control:** We choose OS, Docker version, and when to restart or resize. No platform black boxes.
- **Easier debugging:** All services and logs are on the same machine; we can `docker compose logs` and attach to containers without hopping across services.

**Trade-offs:** We don’t get automatic horizontal scaling or managed patching. For our traffic and team size, that was acceptable. If we outgrow one VM, we can introduce a load balancer and more VMs or migrate to GKE/Cloud Run later.

---

## 3. GCP Secret Manager for application secrets

**Decision:** Store application secrets (API keys, JWT secret, database URLs, etc.) in **GCP Secret Manager** in a single secret (`docsgpt-env`) containing the full `.env` payload. The deploy workflow (or a manual script on the VM) fetches the latest version into `/opt/docsgpt/.env` before starting containers. We do not keep a long-lived `.env` file in the repo or only on disk.

**Why:** We wanted to avoid committing secrets, reduce the risk of leaking a static file from the VM, and make rotation possible without SSHing in to edit files. Secret Manager gives versioning, IAM, and audit logging. The VM’s service account only needs `secretAccessor` on that secret; no JSON keys for the app are stored in GitHub.

**Benefits:**
- **Rotation without SSH:** Add a new secret version in the console or via `gcloud`; the next deploy (or a one-line fetch on the VM) picks it up. No need to copy files or log in to the server to change a key.
- **No secrets in GitHub:** Only the deploy workflow and the VM need access; the VM uses its identity to read the secret. No long-lived `.env` in the repo.
- **Audit trail:** Secret Manager logs who accessed which version and when, which helps with compliance and incident review.
- **Single source of truth:** One secret holds the full env; we don’t juggle multiple secret resources or env files.

**Trade-off:** We still write the secret content to `.env` on the VM at deploy time so containers can mount it. The file exists only briefly before and during runtime; we accept that as a practical compromise. Future improvement could be injecting secrets via runtime environment only (e.g. sidecar or entrypoint that reads from Secret Manager).

---

## 4. Cloud Logging and the Ops Agent for production logs

**Decision:** Send production logs to **Google Cloud Logging** by running the **Ops Agent** on the VM, configured to collect Docker container logs (from the json-file driver) and ship them to Cloud Logging. The backend and worker emit **structured JSON** logs with `severity`, `message`, `service`, and `request_id` so we can filter and build metrics in Logs Explorer.

**Why:** We wanted centralized, queryable logs without building our own log pipeline. Keeping logs only on the VM (e.g. `docker compose logs`) is fine for ad-hoc debugging but doesn’t scale for searching, alerting, or retention. Cloud Logging gives us one place to look, with severity and service name, and the option to add log-based metrics and alerts (e.g. error rate, uptime) later.

**Benefits:**
- **Centralized view:** All container logs in one project; filter by instance, severity, or service (backend vs worker) without SSHing.
- **Structured queries:** JSON fields like `jsonPayload.severity` and `jsonPayload.service` make it easy to find errors or trace a request.
- **Retention and audit:** Logs are stored and searchable in GCP; we’re not dependent on the VM’s disk or log rotation.
- **Path to alerting:** We can define log-based metrics and alerting policies (e.g. when ERROR count spikes or the health endpoint fails) without extra tooling.

**Trade-off:** The Ops Agent adds a small amount of CPU and network on the VM; for our size it’s negligible. We kept the Docker json-file driver with size limits so local disk doesn’t grow unbounded even if the agent is temporarily unavailable.

---

## 5. Full stack on one host with Docker Compose

**Decision:** Run **frontend, backend, worker, Redis, MongoDB, and Qdrant** on the same VM using **Docker Compose** (one compose file for the GCP VM: `docker-compose.gcp.yaml`, with an optional TLS variant that adds Nginx). No managed Redis (Memorystore), managed Mongo (Atlas or DocumentDB), or separate vector DB service.

**Why:** For a single-VM deployment, Compose is the simplest way to define services, dependencies, health checks, and volumes. All communication stays on the Docker network; we don’t pay for or configure managed services. Health checks and `depends_on` ensure a clear startup order (e.g. backend waits for Redis, Mongo, Qdrant; frontend waits for backend).

**Benefits:**
- **One file, one command:** `docker compose up -d` (with the right env file) brings up the whole stack. Easy to replicate locally or on another VM.
- **Explicit dependencies:** Compose and health checks enforce order; we don’t start the backend before Redis is ready.
- **Consistent networking:** Services talk via service names (e.g. `redis`, `mongo`, `qdrant`); no VPC or DNS setup beyond the VM.
- **Portability:** The same compose file (or a close variant) can be used for local dev or a different cloud.

**Trade-offs:** Redis, Mongo, and Qdrant are not highly available; if the VM goes down, everything goes down. We accepted that for this stage. We also publish some internal ports (e.g. 6379, 27017) on the host for debugging; we could tighten that later with `expose` only and no host ports.

---

## 6. TLS with Nginx and Let’s Encrypt

**Decision:** Terminate HTTPS at **Nginx** on the VM using **Let’s Encrypt** certificates. Nginx listens on 80 and 443, proxies to the frontend and backend containers (which only expose ports on the Docker network). Cert renewal is handled by **certbot** on a cron schedule, with a manual or scripted nginx reload after renewal.

**Why:** We wanted HTTPS for the public UI and API (e.g. `https://assistant.mannyroy.com` and `https://assistant-api.mannyroy.com`) without paying for a load balancer or managing certificates in a separate service. Nginx + Let’s Encrypt is a well-understood, free, and flexible pattern. The frontend is built with the API base URL (no port) so the browser always talks to the API over HTTPS.

**Benefits:**
- **Free, trusted certs:** Let’s Encrypt is widely supported and automatable.
- **Single entry point:** Nginx routes by hostname to frontend or backend; we don’t expose the backend port (7091) publicly when TLS is enabled.
- **Familiar ops:** Many teams already know Nginx and certbot; documentation and troubleshooting are easy to find.

**Trade-off:** Cert renewal and nginx reload are our responsibility (cron + reload). We could later add a deploy hook so nginx only reloads when certs actually change.

---

## 7. CI/CD: GitHub Actions, Artifact Registry, SSH deploy

**Decision:** Use **GitHub Actions** to build the backend and frontend images on push to `main`, push them to **GCP Artifact Registry** in the same Canadian region, then **SSH into the VM** and run `docker compose pull` and `up -d`. Image tags are **immutable** (commit SHA). We do not build on the VM; the VM only pulls pre-built images.

**Why:** We wanted a single pipeline that runs on every push, produces traceable images (tag = git SHA), and deploys without manual steps. GitHub Actions keeps CI in our repo and doesn’t tie us to a single cloud’s CI product. Artifact Registry keeps images close to the VM (same region) and uses the VM’s service account for pull (no long-lived Docker credentials on the VM). SSH + compose is straightforward and doesn’t require a separate deploy agent or Kubernetes.

**Benefits:**
- **Traceability:** Every production image is tagged with the commit SHA; we know exactly what is running and can roll back by re-deploying a previous tag.
- **No build on VM:** The VM stays a runtime-only host; no build toolchains, and faster, more reliable deploys.
- **Secrets and logging integrated:** The same workflow can fetch secrets from Secret Manager and write `.env` before compose; the VM already has the Ops Agent for logs.
- **Manual override:** We can re-run the workflow with “Reuse image tag” to redeploy without rebuilding, e.g. after a config or secret change.

**Trade-offs:** We use a GitHub secret (`GCP_SA_KEY`) for a service account JSON key to authenticate the workflow to GCP. A more modern approach is **Workload Identity Federation** so GitHub OIDC issues short-lived tokens and we don’t store a key; we’ve documented that as a future improvement.

---

## 8. Summary table (for quick reference and blogs)

| Decision | Choice | Main benefit |
|----------|--------|--------------|
| Region | Montréal (northamerica-northeast1) | Canadian data residency, single region |
| Compute | Single VM (Compute Engine) | Predictable cost, full control, simple ops |
| Secrets | GCP Secret Manager (`docsgpt-env`) | No secrets in repo; rotate without SSH |
| Logging | Cloud Logging + Ops Agent | Centralized, structured, queryable logs |
| Stack | Docker Compose on one host | One file, one command, clear dependencies |
| TLS | Nginx + Let’s Encrypt | Free HTTPS, single entry point |
| CI/CD | GitHub Actions → Artifact Registry → SSH + compose | Traceable images (SHA), no build on VM |

---

## Related docs

- [SECRET-MANAGER-SETUP.md](SECRET-MANAGER-SETUP.md) – How we set up and use Secret Manager.
- [CLOUD-LOGGING-SETUP.md](CLOUD-LOGGING-SETUP.md) – How we configured the Ops Agent and Cloud Logging.
- [GH-ACTIONS-DEPLOY.md](GH-ACTIONS-DEPLOY.md) – Deploy workflow and secrets.
- [BEST-PRACTICES-REVIEW.md](BEST-PRACTICES-REVIEW.md) – How this setup compares to common best practices.

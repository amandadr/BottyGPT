# Enable TLS (HTTPS) for DocsGPT on the VM

Use Nginx as a reverse proxy with Let's Encrypt. After setup, users use **https://assistant.mannyroy.com** (UI) and **https://assistant-api.mannyroy.com** (API, no port in the URL).

**Quick checklist for API at https://assistant-api.mannyroy.com and redeploy:**  
1. **GitHub secrets:** Set `VITE_API_HOST=https://assistant-api.mannyroy.com` and `VITE_BASE_URL=https://assistant.mannyroy.com` (no trailing slash, no `:7091`).  
2. **VM:** Get Let's Encrypt certs (steps 1–2 below), copy `deployment/docker-compose.gcp-tls.yaml` and `deployment/nginx/` to `/opt/docsgpt`.  
3. **GitHub secret:** Add `USE_TLS` = `true` so the deploy workflow uses the TLS compose.  
4. **Redeploy:** `git push` to `main`; the workflow will build the frontend with the correct API URL and deploy the TLS stack on the VM.

**If you deploy with `docker-compose.gcp.yaml` instead:** That stack binds the frontend to host port **80**. You cannot run **both** `docker-compose.vm-tls.yaml` (nginx on 80) and gcp compose frontend on 80. Either stop the TLS stack (`sudo docker compose -f docker-compose.vm-tls.yaml down`) before using gcp compose on 80, or keep TLS and proxy to the gcp stack (see [VM-PORT-80.md](VM-PORT-80.md)).

## Prerequisites

- DNS: `assistant.mannyroy.com` and `assistant-api.mannyroy.com` point to the VM's external IP.
- GCP firewall allows **tcp:80** and **tcp:443** to the VM.

## 1. Copy TLS files to the VM

On your **Mac** (from repo root). For the **GCP stack** (recommended) use `docker-compose.gcp-tls.yaml`; it uses the same images as `docker-compose.gcp.yaml` with Nginx in front:

```bash
gcloud compute scp deployment/nginx/nginx-tls.conf docsgpt-prod:/opt/docsgpt/ --zone=northamerica-northeast1-a
gcloud compute scp deployment/docker-compose.gcp-tls.yaml docsgpt-prod:/opt/docsgpt/ --zone=northamerica-northeast1-a
```

On the **VM**:

```bash
sudo mkdir -p /opt/docsgpt/nginx
sudo mv /opt/docsgpt/nginx-tls.conf /opt/docsgpt/nginx/
```

## 2. Get Let's Encrypt certs (first time)

SSH to the VM. Free port 80 so certbot can use it (the main stack uses port 80 for the frontend):

```bash
cd /opt/docsgpt
sudo docker compose -f docker-compose.gcp.yaml down
```

Install certbot:

```bash
sudo apt-get update
sudo apt-get install -y certbot
```

Create dir for HTTP-01 challenge (used for renewal later):

```bash
sudo mkdir -p /var/www/certbot
```

Obtain certs (standalone binds port 80):

```bash
sudo certbot certonly --standalone -d assistant.mannyroy.com -d assistant-api.mannyroy.com --non-interactive --agree-tos -m YOUR_EMAIL@example.com
```

Replace `YOUR_EMAIL@example.com` with your email. Certs will be in `/etc/letsencrypt/live/assistant.mannyroy.com/`.

## 3. Start the stack with TLS

**GCP stack (recommended):** Use `docker-compose.gcp-tls.yaml`. It uses the same backend/frontend images (set `IMAGE_TAG` in `.env`). Nginx listens on 80 and 443 and proxies to the frontend and backend containers:

```bash
cd /opt/docsgpt
sudo docker compose -f docker-compose.gcp-tls.yaml --env-file .env up -d
```

- **https://assistant.mannyroy.com** → frontend (no port in URL).
- **https://assistant-api.mannyroy.com** → API (no port in URL; Nginx proxies to backend:7091).

To have **GitHub Actions** deploy with TLS on every push, add secret **USE_TLS** = `true`. The workflow will then use `docker-compose.gcp-tls.yaml`; ensure the VM has this file and the `nginx/` directory.

## 4. Renew certs (automate)

Let's Encrypt certs expire in 90 days. Renew with webroot (Nginx can stay up):

```bash
sudo certbot renew --webroot -w /var/www/certbot --quiet
sudo docker compose -f /opt/docsgpt/docker-compose.gcp-tls.yaml exec nginx nginx -s reload
```

Add a cron job on the VM (e.g. twice monthly):

```bash
sudo crontab -e
```

Add:

```
0 3 1,15 * * certbot renew --webroot -w /var/www/certbot --quiet && sudo docker compose -f /opt/docsgpt/docker-compose.gcp-tls.yaml exec nginx nginx -s reload
```

## 5. Frontend API URL (no port)

With TLS, the API is at **https://assistant-api.mannyroy.com** (no `:7091`). Rebuild the frontend with:

- `VITE_API_HOST=https://assistant-api.mannyroy.com`
- `VITE_BASE_URL=https://assistant.mannyroy.com`

Also keep backend service identity explicit in runtime env:

- `DOCSGPT_SERVICE_NAME=docsgpt-backend`
- `DOCSGPT_SERVICE_NAME=docsgpt-worker` (worker service)

Redeploy the frontend image (CI or local build with those env vars) and backend/worker so HTTPS routes and structured service logs are aligned. The main stack is defined in `deployment/docker-compose.gcp.yaml` (frontend + backend + worker + infra).

# Enable TLS (HTTPS) for DocsGPT on the VM

Use Nginx as a reverse proxy with Let's Encrypt. After setup, users use **https://assistant.mannyroy.com** and **https://assistant-api.mannyroy.com** (no port in the URL).

## Prerequisites

- DNS: `assistant.mannyroy.com` and `assistant-api.mannyroy.com` point to the VM's external IP.
- GCP firewall allows **tcp:80** and **tcp:443** to the VM.

## 1. Copy TLS files to the VM

On your **Mac** (from repo root):

```bash
gcloud compute scp deployment/nginx/nginx-tls.conf deployment/docker-compose.vm-tls.yaml docsgpt-prod:/opt/docsgpt/ --zone=northamerica-northeast1-a
```

On the **VM**:

```bash
sudo mkdir -p /opt/docsgpt/nginx
sudo mv /opt/docsgpt/nginx-tls.conf /opt/docsgpt/nginx/
```

## 2. Get Let's Encrypt certs (first time)

SSH to the VM. Free port 80 so certbot can use it:

```bash
cd /opt/docsgpt
docker compose -f docker-compose.vm.yaml down
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

```bash
docker compose -f docker-compose.vm-tls.yaml --env-file .env up -d
```

Nginx will serve HTTPS on 443 and proxy to the frontend and backend. Open **https://assistant.mannyroy.com** in the browser.

## 4. Renew certs (automate)

Let's Encrypt certs expire in 90 days. Renew with webroot (Nginx can stay up):

```bash
sudo certbot renew --webroot -w /var/www/certbot --quiet
docker compose -f /opt/docsgpt/docker-compose.vm-tls.yaml exec nginx nginx -s reload
```

Add a cron job on the VM (e.g. twice monthly):

```bash
sudo crontab -e
```

Add:

```
0 3 1,15 * * certbot renew --webroot -w /var/www/certbot --quiet && docker compose -f /opt/docsgpt/docker-compose.vm-tls.yaml exec nginx nginx -s reload
```

## 5. Frontend API URL (no port)

With TLS, the API is at **https://assistant-api.mannyroy.com** (no `:7091`). Rebuild the frontend with:

- `VITE_API_HOST=https://assistant-api.mannyroy.com`
- `VITE_BASE_URL=https://assistant.mannyroy.com`

Also keep backend service identity explicit in runtime env:

- `DOCSGPT_SERVICE_NAME=docsgpt-backend`
- `DOCSGPT_SERVICE_NAME=docsgpt-worker` (worker service)

Then redeploy the frontend and backend/worker containers so HTTPS routes and structured service logs are aligned.

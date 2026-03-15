# Free port 80 on the VM (use frontend on 80)

If `docker compose` fails with **port is already allocated** on **80**, something else is bound there. Run these on the VM.

## 1. Identify what holds port 80

```bash
sudo ss -tlnp | grep ':80 '
```

Or:

```bash
sudo lsof -i :80
```

**Docker:** see which container publishes 80:

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -E '80|NAMES'
```

## 2. Most common: old DocsGPT TLS stack (nginx)

If you used [TLS-SETUP.md](TLS-SETUP.md), **nginx** in `docker-compose.vm-tls.yaml` binds **80** and **443**. That stack must be **stopped** before `docker-compose.gcp.yaml` can bind the frontend to 80.

```bash
cd /opt/docsgpt
sudo docker compose -f docker-compose.vm-tls.yaml down
```

If you still need HTTPS later, you can either:

- Put **nginx on the host** (or a small container) in front of the gcp stack: proxy `assistant.mannyroy.com` → `127.0.0.1:80` (frontend container) and `assistant-api` → `127.0.0.1:7091`, **or**
- Redesign TLS so nginx only listens on **443** and use **8080** for HTTP→HTTPS redirect (advanced).

## 3. Old `docker-compose.vm.yaml` stack

That file also maps **80:80** on the frontend. If it’s still running:

```bash
cd /opt/docsgpt
sudo docker compose -f docker-compose.vm.yaml down
```

## 4. Any leftover container on 80

```bash
sudo docker ps -a
```

Stop/remove the container that shows `0.0.0.0:80->` in PORTS, e.g.:

```bash
sudo docker stop <container_name>
sudo docker rm <container_name>   # optional
```

## 5. Host nginx (not in Docker)

```bash
sudo systemctl status nginx
```

If nginx is running and you want the DocsGPT frontend on 80 instead:

```bash
sudo systemctl stop nginx
sudo systemctl disable nginx   # only if you don’t need host nginx
```

## 6. Start the gcp stack on 80

Remove `FRONTEND_HOST_PORT` from `.env` (or set `FRONTEND_HOST_PORT=80`), then:

```bash
cd /opt/docsgpt
sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d
```

Confirm:

```bash
curl -sI http://127.0.0.1:80 | head -1
```

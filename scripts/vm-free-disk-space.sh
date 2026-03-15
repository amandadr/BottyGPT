#!/usr/bin/env bash
# Free disk space on the DocsGPT VM when "no space left on device" during docker pull.
# Run on the VM: bash vm-free-disk-space.sh (or scp this file and run there).
# The backend image includes PyTorch (~2GB+); old images and build cache can fill 50GB.

set -e

echo "=== Disk usage before ==="
df -h /
echo ""
echo "=== Docker disk usage ==="
sudo docker system df 2>/dev/null || true

echo ""
echo "=== Removing stopped containers, unused networks, dangling images (safe) ==="
sudo docker system prune -f

echo ""
echo "=== Removing unused images (not just dangling) ==="
sudo docker image prune -a -f

echo ""
echo "=== Pruning build cache ==="
sudo docker builder prune -af 2>/dev/null || true

echo ""
echo "=== Truncating large container log files (keeps last 0 bytes; optional) ==="
for f in /var/lib/docker/containers/*/*-json.log; do
  if [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null)" -gt 10485760 ]; then
    echo "Truncating $f"
    sudo truncate -s 0 "$f"
  fi
done 2>/dev/null || true

echo ""
echo "=== Clearing journal logs older than 3 days (optional) ==="
sudo journalctl --vacuum-time=3d 2>/dev/null || true

echo ""
echo "=== APT cache (if any) ==="
sudo apt-get clean 2>/dev/null || true

echo ""
echo "=== Disk usage after ==="
df -h /
echo ""
echo "=== Docker disk usage after ==="
sudo docker system df 2>/dev/null || true
echo ""
echo "Done. Re-run your deploy (e.g. sudo docker compose -f docker-compose.gcp.yaml --env-file .env pull && up -d)."

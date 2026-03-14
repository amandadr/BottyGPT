#!/usr/bin/env bash
# Inspect Docker disk usage and remove only safe clutter (keeps buildx cache so backend build doesn't re-run).
# Run from repo root: ./scripts/docker-inspect-and-clean.sh
# Then: ./scripts/push-backend-to-gcp.sh

set -e

echo "=== Docker disk usage ==="
docker system df

echo ""
echo "=== Buildx builders ==="
docker buildx ls

echo ""
echo "=== Pruning stopped containers, unused networks, dangling images (keeps build cache) ==="
docker container prune -f
docker network prune -f
docker image prune -f

echo ""
echo "=== Disk usage after prune ==="
docker system df

echo ""
echo "Done. To push the backend again (build will use cache, only push will run):"
echo "  ./scripts/push-backend-to-gcp.sh"
echo ""
echo "To also prune build cache (frees more space but next build will re-run pip install):"
echo "  docker buildx prune -f"
echo ""
echo "If push still takes too long: consider building and pushing from CI (GitHub Actions) instead of your Mac."

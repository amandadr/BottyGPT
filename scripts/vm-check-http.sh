#!/usr/bin/env bash
# Run ON THE VM to verify the frontend is listening and reachable locally.
# Usage: cd /opt/docsgpt && bash vm-check-http.sh

set -e

PORT="${FRONTEND_HOST_PORT:-80}"
echo "=== Frontend port (from .env or default): $PORT"
echo ""

echo "=== 1. Frontend container running? ==="
sudo docker ps --filter "name=frontend" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "=== 2. Is anything listening on 0.0.0.0:$PORT or :::$PORT? ==="
sudo ss -tlnp | grep -E ":$PORT |:::$PORT " || echo "(nothing found - frontend may not be bound)"
echo ""

echo "=== 3. Curl localhost:$PORT (first line of response) ==="
curl -sI "http://127.0.0.1:${PORT}" | head -1 || echo "Curl failed - connection refused or timeout"
echo ""

echo "=== 4. VM external IP (use this in browser) ==="
curl -sS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || echo "Could not read metadata (not on GCP?)"
echo ""

echo "If step 3 shows HTTP/1.1 200 but browser still fails, the GCP firewall is blocking. Open tcp:$PORT with target tag http-server and add that tag to this instance."

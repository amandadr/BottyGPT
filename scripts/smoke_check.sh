#!/usr/bin/env bash
# Post-deploy smoke check for DocsGPT stack (Plan 2.0).
# Usage: ./scripts/smoke_check.sh [BASE_URL]
# Default BASE_URL is http://localhost:7091 (e.g. when backend port is exposed on host).

set -e

BASE_URL="${1:-http://localhost:7091}"

echo "Smoke check: ${BASE_URL}"
echo "---"

if ! curl -sf "${BASE_URL}/api/health" > /dev/null; then
  echo "FAIL: GET ${BASE_URL}/api/health"
  exit 1
fi
echo "OK: GET ${BASE_URL}/api/health"

READY_RESPONSE=$(curl -sf "${BASE_URL}/api/ready")
READY_STATUS=$(echo "$READY_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
if [ "$READY_STATUS" != "ready" ]; then
  echo "FAIL: GET ${BASE_URL}/api/ready (status=${READY_STATUS})"
  echo "$READY_RESPONSE"
  exit 1
fi
echo "OK: GET ${BASE_URL}/api/ready (status=${READY_STATUS})"

echo "---"
echo "Smoke check passed."

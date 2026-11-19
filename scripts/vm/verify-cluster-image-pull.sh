#!/usr/bin/env bash
# Diagnose Harbor reachability and pull secret on the VM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

HARBOR_SERVER="${HARBOR_SERVER:-harbor.ldc.opstree.dev}"
TEST_IMAGE="${HARBOR_SERVER}/coe/uniteconpro-backend-prod:latest"

echo "=== DNS ==="
getent hosts "$HARBOR_SERVER" || { echo "Cannot resolve $HARBOR_SERVER (VPN/DNS?)"; exit 1; }

echo "=== Harbor API ==="
if [[ -n "${HARBOR_USERNAME:-}" && -n "${HARBOR_PASSWORD:-}" ]]; then
  code=$(curl -sS -o /dev/null -w '%{http_code}' -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" \
    "https://${HARBOR_SERVER}/v2/")
  echo "GET /v2/ HTTP $code (401 or 200 is OK with creds)"
else
  echo "Skip API auth — no deploy/harbor.env"
fi

echo "=== Kubernetes secrets ==="
for ns in databases spendsmart; do
  if kubectl get secret harbor-regcred -n "$ns" &>/dev/null; then
    echo "OK harbor-regcred in $ns"
  else
    echo "MISSING harbor-regcred in $ns — run: bash scripts/vm/create-harbor-pull-secret.sh"
  fi
done

echo "=== Sample pod events (databases) ==="
kubectl get events -n databases --sort-by='.lastTimestamp' 2>/dev/null | tail -8 || true

echo "=== Optional: docker pull (on the node) ==="
if command -v docker >/dev/null && [[ -n "${HARBOR_USERNAME:-}" ]]; then
  printf '%s' "$HARBOR_PASSWORD" | docker login "$HARBOR_SERVER" -u "$HARBOR_USERNAME" --password-stdin
  docker pull "$TEST_IMAGE" && echo "OK pulled $TEST_IMAGE"
fi
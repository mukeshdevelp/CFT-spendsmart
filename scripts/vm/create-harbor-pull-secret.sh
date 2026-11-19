#!/usr/bin/env bash
# Create harbor-regcred in namespaces that pull private Harbor images.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

HARBOR_SERVER="${HARBOR_SERVER:-harbor.ldc.opstree.dev}"
NAMESPACES="${1:-databases spendsmart}"

if [[ -z "${HARBOR_USERNAME:-}" || -z "${HARBOR_PASSWORD:-}" ]]; then
  echo "ERROR: Set HARBOR_USERNAME and HARBOR_PASSWORD in deploy/harbor.env" >&2
  exit 1
fi

for ns in $NAMESPACES; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret docker-registry harbor-regcred \
    --docker-server="${HARBOR_SERVER}" \
    --docker-username="$HARBOR_USERNAME" \
    --docker-password="$HARBOR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" patch serviceaccount default \
    -p '{"imagePullSecrets":[{"name":"harbor-regcred"}]}' --type=merge 2>/dev/null || true
done

echo "harbor-regcred applied in: $NAMESPACES"
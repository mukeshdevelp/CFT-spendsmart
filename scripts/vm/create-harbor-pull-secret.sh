#!/usr/bin/env bash
# Create docker-registry secret in namespaces that pull from Harbor.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

HARBOR_SERVER="${HARBOR_SERVER:-harbor.ldc.opstree.dev}"
NAMESPACES="${1:-databases spendsmart}"

if [[ -z "${HARBOR_USERNAME:-}" || -z "${HARBOR_PASSWORD:-}" ]]; then
  echo "HARBOR_USERNAME/HARBOR_PASSWORD not set — skip harbor-regcred (only for public images)."
  exit 0
fi

for ns in $NAMESPACES; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret docker-registry harbor-regcred \
    --docker-server="$HARBOR_SERVER" \
    --docker-username="$HARBOR_USERNAME" \
    --docker-password="$HARBOR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
done
echo "Harbor pull secret applied to: $NAMESPACES"
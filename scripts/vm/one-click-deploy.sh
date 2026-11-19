#!/usr/bin/env bash
# Deploy SpendSmart on an existing Kubernetes cluster (Helm only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required (configure KUBECONFIG for your cluster)." >&2
  exit 1
}
kubectl cluster-info >/dev/null 2>&1 || {
  echo "Cannot reach the cluster — set KUBECONFIG and check access." >&2
  exit 1
}

echo "=== SpendSmart Helm deploy $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
bash "${ROOT}/scripts/vm/deploy-spendsmart.sh"
echo "=== Done ==="
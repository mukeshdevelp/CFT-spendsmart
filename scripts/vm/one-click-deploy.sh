#!/usr/bin/env bash
# One-click SpendSmart on a single GCP VM (k3s + in-cluster DBs + Helm).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-/etc/k3s/k3s.yaml}"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

echo "=== SpendSmart VM deploy $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

bash "${ROOT}/scripts/vm/install-k3s.sh"
bash "${ROOT}/scripts/vm/create-harbor-pull-secret.sh" "databases spendsmart"
bash "${ROOT}/scripts/vm/bootstrap-databases.sh"
bash "${ROOT}/scripts/vm/deploy-spendsmart.sh"

echo "=== Done ==="
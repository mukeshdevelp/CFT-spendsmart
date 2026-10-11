#!/usr/bin/env bash
# Re-run cluster bootstrap on an existing bastion (after fixing SG or uploading assets).
set -euo pipefail
export EKS_REGION="${EKS_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-spendsmart}"
export POSTGRES_SECRET_NAME="${POSTGRES_SECRET_NAME:-spendsmart-dev/postgres}"
export CLICKHOUSE_SECRET_NAME="${CLICKHOUSE_SECRET_NAME:-spendsmart-dev/clickhouse}"
export KUBECTL_VERSION="${KUBECTL_VERSION:-1.36.2}"
export MANIFESTS_DIR="${MANIFESTS_DIR:-/opt/spendsmart/manifests}"
SCRIPT="${SCRIPT:-/opt/spendsmart/cluster-bootstrap.sh}"
if [[ ! -x "$SCRIPT" ]]; then
  echo "Missing $SCRIPT — run scripts/sync-bastion-assets.sh and aws s3 sync on the bastion first."
  exit 1
fi
exec sudo -E "$SCRIPT"

#!/usr/bin/env bash
# Re-run cluster bootstrap on an existing bastion (after fixing SG or uploading assets).
set -euo pipefail
export EKS_REGION="${EKS_REGION:-ca-central-1}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-spendsmart}"
export POSTGRES_SECRET_NAME="${POSTGRES_SECRET_NAME:-spendsmart-dev/postgres}"
export CLICKHOUSE_SECRET_NAME="${CLICKHOUSE_SECRET_NAME:-spendsmart-dev/clickhouse}"
export KUBECTL_VERSION="${KUBECTL_VERSION:-1.36.2}"
export MANIFESTS_DIR="${MANIFESTS_DIR:-/opt/spendsmart/manifests}"
ASSET_DIR="${ASSET_DIR:-/opt/spendsmart}"
for f in install-kubectl.sh configure-kubeconfig.sh cluster-bootstrap.sh; do
  if [[ ! -x "${ASSET_DIR}/${f}" ]]; then
    echo "Missing ${ASSET_DIR}/${f} — sync bastion-assets from S3 first (Jenkinsfile or sync-bastion-assets.sh)."
    exit 1
  fi
done
sudo KUBECTL_VERSION="$KUBECTL_VERSION" "${ASSET_DIR}/install-kubectl.sh"
sudo EKS_REGION="$EKS_REGION" EKS_CLUSTER_NAME="$EKS_CLUSTER_NAME" "${ASSET_DIR}/configure-kubeconfig.sh"
exec sudo -E "${ASSET_DIR}/cluster-bootstrap.sh"

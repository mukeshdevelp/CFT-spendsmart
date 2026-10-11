#!/usr/bin/env bash
# Upload bastion bootstrap script and Kubernetes manifests to the CFN template bucket.
set -euo pipefail
BUCKET="${1:?usage: sync-bastion-assets.sh <cfn-template-bucket> [region]}"
REGION="${2:-us-east-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

install -D -m 0755 "$ROOT/modules/bastion/scripts/cluster-bootstrap.sh" "$STAGING/cluster-bootstrap.sh"
install -D -m 0755 "$ROOT/modules/bastion/scripts/install-kubectl.sh" "$STAGING/install-kubectl.sh"
install -D -m 0755 "$ROOT/modules/bastion/scripts/configure-kubeconfig.sh" "$STAGING/configure-kubeconfig.sh"
install -D -m 0644 "$ROOT/modules/bastion/manifests/databases.yaml" "$STAGING/manifests/databases.yaml"
install -D -m 0755 "$ROOT/scripts/bastion-apply-app-secrets.sh" "$STAGING/bastion-apply-app-secrets.sh"
install -D -m 0755 "$ROOT/scripts/bastion-apply-chart-secrets.sh" "$STAGING/bastion-apply-chart-secrets.sh"
install -D -m 0755 "$ROOT/scripts/bastion-helm-install.sh" "$STAGING/bastion-helm-install.sh"
install -D -m 0755 "$ROOT/scripts/bastion-deploy-keycloak.sh" "$STAGING/bastion-deploy-keycloak.sh"
install -D -m 0755 "$ROOT/scripts/bastion-configure-keycloak-realm.sh" "$STAGING/bastion-configure-keycloak-realm.sh"

aws s3 sync "$STAGING/" "s3://${BUCKET}/bastion-assets/" --region "$REGION"
echo "Synced to s3://${BUCKET}/bastion-assets/"

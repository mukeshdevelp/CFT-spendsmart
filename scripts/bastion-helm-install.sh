#!/usr/bin/env bash
# Run on bastion: helm upgrade --install spendsmart chart from GitHub branch.
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"

VALUES_FILE="${VALUES_FILE:-/tmp/helm-values-rendered.yaml}"
CHART_REPO="${CHART_REPO:-https://github.com/OT-CONTAINER-KIT/helm-charts.git}"
CHART_BRANCH="${CHART_BRANCH:-feature/spendsmart-helm-chart}"
CHART_SUBPATH="${CHART_SUBPATH:-charts/spendsmart}"
RELEASE_NAME="${RELEASE_NAME:-spendsmart}"
NAMESPACE="${NAMESPACE:-spendsmart}"
HELM_TIMEOUT="${HELM_TIMEOUT:-20m}"
HELM_WAIT="${HELM_WAIT:-true}"

command -v git >/dev/null || sudo dnf install -y git
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
git clone --depth 1 --branch "$CHART_BRANCH" "$CHART_REPO" "$WORKDIR/repo"
CHART_DIR="$WORKDIR/repo/$CHART_SUBPATH"
test -f "$CHART_DIR/Chart.yaml"

helm lint "$CHART_DIR" -f "$VALUES_FILE"
WAIT_ARGS=()
if [ "$HELM_WAIT" = "true" ]; then
  WAIT_ARGS=(--wait --timeout "$HELM_TIMEOUT")
fi
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  "${WAIT_ARGS[@]}"

kubectl get deploy,svc,pods,cronjob -n "$NAMESPACE"

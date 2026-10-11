#!/usr/bin/env bash
# Run on bastion: helm upgrade --install spendsmart chart from GitHub branch.
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"
DEPLOY_CONTEXT_FILE="${DEPLOY_CONTEXT_FILE:-/tmp/helm-deploy-context.env}"
if [ -f "$DEPLOY_CONTEXT_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$DEPLOY_CONTEXT_FILE"
  set +a
fi

VALUES_FILE="${VALUES_FILE:-/tmp/helm-values-rendered.yaml}"
CHART_REPO="${CHART_REPO:-https://github.com/OT-CONTAINER-KIT/helm-charts.git}"
CHART_BRANCH="${CHART_BRANCH:-feature/spendsmart-helm-chart}"
CHART_SUBPATH="${CHART_SUBPATH:-charts/spendsmart}"
RELEASE_NAME="${RELEASE_NAME:-spendsmart}"
NAMESPACE="${NAMESPACE:-spendsmart}"
HELM_TIMEOUT="${HELM_TIMEOUT:-20m}"
HELM_WAIT="${HELM_WAIT:-true}"
ALB_TARGET_PORT="${ALB_TARGET_PORT:-30080}"
PATCH_FRONTEND_NODEPORT="${PATCH_FRONTEND_NODEPORT:-true}"

patch_frontend_nodeport() {
  local svc="${RELEASE_NAME}-frontend"
  if [ "$PATCH_FRONTEND_NODEPORT" != "true" ]; then
    return 0
  fi
  if ! kubectl get svc "$svc" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Skip NodePort patch: Service $svc not found"
    return 0
  fi
  echo "Patching $svc NodePort -> ${ALB_TARGET_PORT} (ALB target group port)"
  kubectl patch svc "$svc" -n "$NAMESPACE" --type merge -p "{
    \"spec\": {
      \"type\": \"NodePort\",
      \"ports\": [{
        \"name\": \"http\",
        \"port\": 80,
        \"targetPort\": 80,
        \"nodePort\": ${ALB_TARGET_PORT},
        \"protocol\": \"TCP\"
      }]
    }
  }"
}

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
if ! helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  "${WAIT_ARGS[@]}"; then
  echo "helm upgrade failed; pod status:"
  kubectl get pods -n "$NAMESPACE" -o wide || true
  kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -30 || true
  exit 1
fi

patch_frontend_nodeport

kubectl get deploy,svc,pods,cronjob -n "$NAMESPACE"

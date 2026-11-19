#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHART="${ROOT}/charts/spendsmart"
NAMESPACE="${NAMESPACE:-spendsmart}"
VALUES_A="${ROOT}/deploy/values-a-file.yaml"

if [[ -f "$VALUES_A" ]]; then
  echo "Using deploy/values-a-file.yaml"
  helm upgrade --install spendsmart "$CHART" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "${CHART}/values.yaml" \
    -f "${CHART}/values-vm.yaml" \
    -f "$VALUES_A" \
    --wait --timeout 30m
  kubectl -n "$NAMESPACE" get deploy,svc,pods
  exit 0
fi

# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

if [[ -z "${GPG_KEY:-}" ]]; then
  echo "Create deploy/values-a-file.yaml from deploy/values-a-file.yaml.example" >&2
  echo "Or set deploy/gpg.env with GPG_KEY=..." >&2
  exit 1
fi

if [[ -f "${ROOT}/deploy/.db.generated.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT}/deploy/.db.generated.env"
  set +a
fi
if [[ -z "${POSTGRES_PASSWORD:-}" || -z "${CLICKHOUSE_PASSWORD:-}" ]]; then
  echo "Set POSTGRES_PASSWORD and CLICKHOUSE_PASSWORD in deploy/db.env or run bootstrap-databases.sh" >&2
  exit 1
fi

PUBLIC_HOST="${PUBLIC_HOST:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
[[ -n "$PUBLIC_HOST" ]] || { echo "Set PUBLIC_HOST in deploy/vm.env" >&2; exit 1; }

bash "${ROOT}/scripts/vm/create-harbor-pull-secret.sh" spendsmart
kubectl apply -f "${ROOT}/kubernetes/vm/database-aliases.yaml"

KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-spendsmart-keycloak-admin}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
API_URL="http://${PUBLIC_HOST}:30081"
KC_URL="http://${PUBLIC_HOST}:30083"

kubectl -n "$NAMESPACE" create secret generic encryption-key \
  --from-literal=GPG_KEY="$GPG_KEY" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic clickhouse \
  --from-literal=CLICKHOUSE_HOST=clickhouse \
  --from-literal=CLICKHOUSE_PORT=8123 \
  --from-literal=CLICKHOUSE_USER=dba \
  --from-literal=CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" \
  --from-literal=CLICKHOUSE_DATABASE=cost \
  --from-literal=CLICKHOUSE_TABLE=service_costs \
  --from-literal=CLICKHOUSE_TLS=false \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic clickhouse-db \
  --from-literal=CLICKHOUSE_HOST=clickhouse \
  --from-literal=CLICKHOUSE_PORT=8123 \
  --from-literal=CLICKHOUSE_USER=dba \
  --from-literal=CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" \
  --from-literal=CLICKHOUSE_DATABASE=cost \
  --from-literal=CLICKHOUSE_TABLE=service_costs \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic keycloak-admin \
  --from-literal=username=admin \
  --from-literal=password="$KEYCLOAK_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

GEN="${ROOT}/deploy/generated-public-urls.yaml"
cat >"$GEN" <<EOF
global:
  publicHost: "${PUBLIC_HOST}"
frontend:
  image:
    tag: "${IMAGE_TAG}"
  configMap:
    data:
      VITE_API_BASE_URL: "${API_URL}"
      VITE_KEYCLOAK_URL: "${KC_URL}"
backend:
  image:
    tag: "${IMAGE_TAG}"
engine:
  image:
    tag: "${IMAGE_TAG}"
EOF

helm upgrade --install spendsmart "$CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "${CHART}/values.yaml" \
  -f "${CHART}/values-vm.yaml" \
  -f "$GEN" \
  --wait --timeout 30m

kubectl -n "$NAMESPACE" get deploy,svc,pods
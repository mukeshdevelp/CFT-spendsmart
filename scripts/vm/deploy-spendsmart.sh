#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

NAMESPACE="${NAMESPACE:-spendsmart}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-spendsmart-keycloak-admin}"
CHART="${ROOT}/charts/spendsmart"

if [[ -z "${GPG_KEY:-}" ]]; then
  echo "GPG_KEY is required (deploy/gpg.env)." >&2
  exit 1
fi

if [[ -f "${ROOT}/deploy/.db.generated.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT}/deploy/.db.generated.env"
  set +a
fi
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?bootstrap-databases first}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:?bootstrap-databases first}"

PUBLIC_HOST="${PUBLIC_HOST:-}"
if [[ -z "$PUBLIC_HOST" ]]; then
  PUBLIC_HOST="$(curl -sf -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || true)"
fi
if [[ -z "$PUBLIC_HOST" ]]; then
  PUBLIC_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[[ -n "$PUBLIC_HOST" ]] || { echo "Set PUBLIC_HOST in deploy/vm.env" >&2; exit 1; }

API_URL="http://${PUBLIC_HOST}:30081"
KC_URL="http://${PUBLIC_HOST}:30083"
CS_URL="http://${PUBLIC_HOST}:30082"

command -v helm >/dev/null || {
  curl -fsSL https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz -o /tmp/helm.tar.gz
  tar -xzf /tmp/helm.tar.gz -C /tmp && sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
}

bash "${ROOT}/scripts/vm/create-harbor-pull-secret.sh" "spendsmart"

kubectl apply -f "${ROOT}/kubernetes/vm/database-aliases.yaml"

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
      VITE_CLOUD_SENTRY_API_BASE_URL: ""
      VITE_KEYCLOAK_URL: "${KC_URL}"
  nginx:
    csp:
      connectSrc:
        - "'self'"
        - "${API_URL}"
        - "${KC_URL}"
        - "wss:"
      frameSrc:
        - "'self'"
        - "${KC_URL}"
        - "https:"
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
echo ""
echo "SpendSmart UI:  http://${PUBLIC_HOST}:30080"
echo "API (NodePort): http://${PUBLIC_HOST}:30081"
echo "Keycloak:       http://${PUBLIC_HOST}:30083"
echo "Open GCP firewall for TCP 30080-30083 if needed."
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-$(openssl rand -hex 16)}"

kubectl create namespace databases --dry-run=client -o yaml | kubectl apply -f -

kubectl -n databases create secret generic postgres-auth \
  --from-literal=username=dbadmin \
  --from-literal=password="$POSTGRES_PASSWORD" \
  --from-literal=database=cloudsentry \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n databases create secret generic clickhouse-auth \
  --from-literal=username=dba \
  --from-literal=password="$CLICKHOUSE_PASSWORD" \
  --from-literal=database=cost \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ROOT}/kubernetes/vm/databases.yaml"

kubectl -n databases rollout status statefulset/postgres --timeout=900s
kubectl -n databases rollout status statefulset/clickhouse --timeout=900s

kubectl -n databases exec statefulset/clickhouse -- clickhouse-client --query "CREATE DATABASE IF NOT EXISTS cost" || true
kubectl -n databases exec statefulset/clickhouse -- clickhouse-client --query "GRANT ALL ON cost.* TO dba" || true

echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >"${ROOT}/deploy/.db.generated.env"
echo "CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}" >>"${ROOT}/deploy/.db.generated.env"
chmod 600 "${ROOT}/deploy/.db.generated.env" 2>/dev/null || true
echo "Databases ready (credentials in deploy/.db.generated.env)."
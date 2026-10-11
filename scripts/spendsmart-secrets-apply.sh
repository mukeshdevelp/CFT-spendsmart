#!/usr/bin/env bash
# Create spendsmart app secrets matching local cluster key layout (values from env / SM).
# Used on bastion or deployment host; same keys as export-spendsmart-cluster-spec.sh.
set -euo pipefail
NS="${K8S_NAMESPACE:-spendsmart}"
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"

: "${HARBOR_SERVER:=harbor.ldc.opstree.dev}"
: "${HARBOR_USER:?}"
: "${HARBOR_PASS:?}"
: "${GPG_KEY:?}"
: "${CH_HOST:=clickhouse}"
: "${CH_PORT:=8123}"
: "${CH_USER:?}"
: "${CH_PASS:?}"
: "${CH_DB:=cost}"
: "${CH_TABLE:=service_costs}"
: "${CH_TLS:=false}"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret docker-registry harbor-ldc-coe-regcred \
  --docker-server="$HARBOR_SERVER" \
  --docker-username="$HARBOR_USER" \
  --docker-password="$HARBOR_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic encryption-key \
  --from-literal=GPG_KEY="$GPG_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic clickhouse \
  --from-literal=CLICKHOUSE_HOST="$CH_HOST" \
  --from-literal=CLICKHOUSE_PORT="$CH_PORT" \
  --from-literal=CLICKHOUSE_USER="$CH_USER" \
  --from-literal=CLICKHOUSE_PASSWORD="$CH_PASS" \
  --from-literal=CLICKHOUSE_DATABASE="$CH_DB" \
  --from-literal=CLICKHOUSE_TABLE="$CH_TABLE" \
  --from-literal=CLICKHOUSE_TLS="$CH_TLS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic clickhouse-db \
  --from-literal=CLICKHOUSE_HOST="$CH_HOST" \
  --from-literal=CLICKHOUSE_PORT="$CH_PORT" \
  --from-literal=CLICKHOUSE_USER="$CH_USER" \
  --from-literal=CLICKHOUSE_PASSWORD="$CH_PASS" \
  --from-literal=CLICKHOUSE_DATABASE="$CH_DB" \
  --from-literal=CLICKHOUSE_TABLE="$CH_TABLE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets applied in $NS (keys match local cluster spec)"

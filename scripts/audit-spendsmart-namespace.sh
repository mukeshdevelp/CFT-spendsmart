#!/usr/bin/env bash
# Compare local Minikube spendsmart ns with the local Harbor guide (Readme steps 6, 12–15).
# Usage: ./scripts/audit-spendsmart-namespace.sh [namespace]
set -euo pipefail
NS="${1:-spendsmart}"

echo "=== namespace ${NS} ==="
kubectl get ns "$NS" >/dev/null

echo "=== secrets (required names) ==="
for s in harbor-ldc-coe-regcred encryption-key clickhouse clickhouse-db; do
  kubectl get secret "$s" -n "$NS" -o custom-columns=NAME:.metadata.name,TYPE:.type,DATA:.data --no-headers
done

echo "=== clickhouse secret keys (expect 7) ==="
kubectl get secret clickhouse -n "$NS" -o json | python3 -c '
import json,sys
keys=sorted(json.load(sys.stdin)["data"].keys())
print(keys)
assert len(keys)==7, keys
for k in ["CLICKHOUSE_HOST","CLICKHOUSE_PORT","CLICKHOUSE_USER","CLICKHOUSE_PASSWORD","CLICKHOUSE_DATABASE","CLICKHOUSE_TABLE","CLICKHOUSE_TLS"]:
    assert k in keys, k
'

echo "=== clickhouse-db secret keys (expect 6) ==="
kubectl get secret clickhouse-db -n "$NS" -o json | python3 -c '
import json,sys
keys=sorted(json.load(sys.stdin)["data"].keys())
print(keys)
assert len(keys)==6, keys
'

echo "=== encryption-key (expect GPG_KEY) ==="
kubectl get secret encryption-key -n "$NS" -o json | python3 -c '
import json,sys
keys=sorted(json.load(sys.stdin)["data"].keys())
print(keys)
assert keys == ["GPG_KEY"], f"expected GPG_KEY only, got {keys}"
'

echo "=== workload images ==="
kubectl get deploy,cronjob -n "$NS" -o custom-columns=KIND:.kind,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image --no-headers 2>/dev/null || true

echo "=== configmaps (Helm chart) ==="
kubectl get configmaps -n "$NS" | grep -E 'uniteconpro-frontend|spendsmart-frontend-nginx' || kubectl get configmaps -n "$NS"

echo "OK: ${NS} matches local guide secret/configmap layout"

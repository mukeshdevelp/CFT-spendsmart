#!/usr/bin/env bash
# Run on bastion via SSM for Jenkins failure diagnostics.
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"
NS="${1:-spendsmart}"

echo "=== nodes ==="
kubectl get nodes -o wide 2>/dev/null || true
echo "=== pods -n ${NS} ==="
kubectl get pods -n "$NS" -o wide 2>/dev/null || true
echo "=== events -n ${NS} (last 25) ==="
kubectl get events -n "$NS" --sort-by=.lastTimestamp 2>/dev/null | tail -25 || true
echo "=== not-ready pods (describe) ==="
for p in $(kubectl get pods -n "$NS" --field-selector=status.phase!=Running --no-headers 2>/dev/null | awk '{print $1}'); do
  kubectl describe pod -n "$NS" "$p" 2>/dev/null | tail -40 || true
done

#!/usr/bin/env bash
set -euo pipefail

if command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
  echo "Kubernetes already available: $(kubectl version --short 2>/dev/null || kubectl version)"
  exit 0
fi

echo "Installing k3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

export KUBECONFIG="${KUBECONFIG:-/etc/k3s/k3s.yaml}"
kubectl wait --for=condition=Ready node --all --timeout=600s
echo "k3s ready."
#!/bin/bash
# Install kubectl to /usr/local/bin (on PATH for root and ec2-user).
set -euo pipefail
KUBECTL_VERSION="${KUBECTL_VERSION:-1.36.2}"
command -v curl >/dev/null || dnf install -y curl-minimal
if command -v kubectl >/dev/null; then
  kubectl version --client --short 2>/dev/null || kubectl version --client
  exit 0
fi
curl -fL -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client

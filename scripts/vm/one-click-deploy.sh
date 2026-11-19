#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v kubectl >/dev/null
kubectl cluster-info >/dev/null
bash "${ROOT}/scripts/vm/deploy-spendsmart.sh"
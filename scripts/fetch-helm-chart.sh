#!/usr/bin/env bash
# Refresh local copy of OT-CONTAINER-KIT spendsmart chart (for lint/template review).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/vendor/helm-charts"
BRANCH="${CHART_BRANCH:-feature/spendsmart-helm-chart}"
REPO="${CHART_REPO:-https://github.com/OT-CONTAINER-KIT/helm-charts.git}"

rm -rf "$DEST"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$DEST"
echo "Chart at ${DEST}/charts/spendsmart"
helm lint "${DEST}/charts/spendsmart" -f "${ROOT}/client-a-values.yaml" || true

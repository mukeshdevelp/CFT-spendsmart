#!/usr/bin/env bash
# Test Harbor reachability + credentials (run on VM or PC with docker).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/load-deploy-env.sh"

HARBOR_SERVER="${HARBOR_SERVER:-harbor.ldc.opstree.dev}"
TEST_IMAGE="${HARBOR_SERVER}/coe/uniteconpro-backend-prod:${HARBOR_TEST_TAG:-latest}"

: "${HARBOR_USERNAME:?Set HARBOR_USERNAME (or deploy/harbor.env)}"
: "${HARBOR_PASSWORD:?Set HARBOR_PASSWORD}"

printf '%s' "$HARBOR_PASSWORD" | docker login "$HARBOR_SERVER" -u "$HARBOR_USERNAME" --password-stdin
docker pull "$TEST_IMAGE"
echo "OK: Harbor login and pull work for ${TEST_IMAGE}"
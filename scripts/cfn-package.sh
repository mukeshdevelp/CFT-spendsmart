#!/usr/bin/env bash
# Package main.yml nested templates to S3 (same as Jenkins "Package and validate" stage).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
BUCKET="${CFN_TEMPLATE_BUCKET:-spendsmart-cfn-packages}"
OUT="${PACKAGED_TEMPLATE:-${ROOT}/packaged.yml}"

bash "${ROOT}/scripts/sync-bastion-assets.sh" "$BUCKET" "$REGION"
aws cloudformation package \
  --template-file "${ROOT}/main.yml" \
  --s3-bucket "$BUCKET" \
  --output-template-file "$OUT" \
  --region "$REGION"
aws cloudformation validate-template --template-body "file://${OUT}" --region "$REGION" >/dev/null
echo "Packaged: ${OUT} → s3://${BUCKET}/"

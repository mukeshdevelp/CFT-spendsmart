#!/usr/bin/env bash
# Local deploy: loads deploy/harbor.env and passes Harbor* into CloudFormation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${HARBOR_ENV_FILE:-${ROOT}/deploy/harbor.env}"
STACK_NAME="${CFN_STACK_NAME:-spendsmart-dev}"
REGION="${AWS_REGION:-us-east-1}"
TEMPLATE="${PACKAGED_TEMPLATE:-${ROOT}/packaged.yml}"
PARAMS_FILE="${ROOT}/.cfn-parameters.local.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Create ${ENV_FILE} from deploy/harbor.env.example (set HARBOR_PASSWORD)."
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${HARBOR_USERNAME:?}"
: "${HARBOR_PASSWORD:?}"

export HARBOR_USERNAME HARBOR_PASSWORD
export DEPLOY_SPENDSMART=true
export CFN_PARAMETERS_BASE="${ROOT}/parameters.json"
export CFN_PARAMETERS_OUT="$PARAMS_FILE"
python3 "${ROOT}/scripts/merge-cfn-parameters.py"

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws cloudformation update-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://${TEMPLATE}" \
    --parameters "file://${PARAMS_FILE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"
  aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
else
  aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://${TEMPLATE}" \
    --parameters "file://${PARAMS_FILE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"
  aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
fi

echo "Stack ${STACK_NAME} deployed."

# ALB DNS + app URLs from stack outputs (main.yml AlbDnsName / SpendSmart*Url)
if eval "$(bash "${ROOT}/scripts/cfn-alb-urls.sh")" 2>/dev/null; then
  echo ""
  echo "=== Application URLs (from CloudFormation) ==="
  echo "  ALB DNS:     ${ALB_DNS}"
  echo "  Frontend:    ${FRONTEND_URL}"
  echo "  Backend API: ${BACKEND_URL}"
  echo "  Keycloak:    ${KEYCLOAK_URL}"
  echo ""
  if [[ -f "${ROOT}/deploy/spendsmart-cluster-spec.json" ]]; then
    python3 "${ROOT}/scripts/render-helm-values-from-spec.py" \
      --stack-name "$STACK_NAME" \
      --region "$REGION" || true
  else
    echo "Tip: run ./scripts/export-spendsmart-cluster-spec.sh then render-helm-values-from-spec.py (ALB auto from stack)."
  fi
else
  echo "AlbDnsName not available yet (stack still rolling back or Alb not created). Check:"
  echo "  aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query 'Stacks[0].Outputs'"
fi

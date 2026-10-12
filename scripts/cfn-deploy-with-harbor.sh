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

stack_status() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo 'DOES_NOT_EXIST'
}

wait_for_stable_stack() {
  local status
  status="$(stack_status)"
  case "$status" in
    DOES_NOT_EXIST)
      return 0
      ;;
    DELETE_IN_PROGRESS)
      echo "Stack ${STACK_NAME} is deleting; waiting for DELETE_COMPLETE..."
      aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
      return 0
      ;;
    DELETE_FAILED)
      echo "Stack ${STACK_NAME} is DELETE_FAILED (often S3 DataBucket not empty)."
      echo "Empty bucket from parameters (e.g. athena-results-spendsmart-dev), then:"
      echo "  aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}"
      echo "  aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region ${REGION}"
      exit 1
      ;;
    CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS|UPDATE_COMPLETE_CLEANUP_IN_PROGRESS|\
    UPDATE_ROLLBACK_IN_PROGRESS|ROLLBACK_IN_PROGRESS|REVIEW_IN_PROGRESS)
      echo "Stack ${STACK_NAME} is busy (${status}); wait for a terminal state, then re-run this script."
      exit 1
      ;;
    *)
      return 0
      ;;
  esac
}

cfn_create() {
  aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://${TEMPLATE}" \
    --parameters "file://${PARAMS_FILE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"
  aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
}

cfn_update() {
  if ! aws cloudformation update-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://${TEMPLATE}" \
    --parameters "file://${PARAMS_FILE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" 2>"${TMPDIR:-/tmp}/cfn-update.err"; then
    if grep -q 'No updates are to be performed' "${TMPDIR:-/tmp}/cfn-update.err"; then
      echo "No CloudFormation changes to apply."
      return 0
    fi
    cat "${TMPDIR:-/tmp}/cfn-update.err" >&2
    return 1
  fi
  aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
}

wait_for_stable_stack
status="$(stack_status)"
case "$status" in
  DOES_NOT_EXIST)
    cfn_create
    ;;
  CREATE_COMPLETE|UPDATE_COMPLETE)
    cfn_update
    ;;
  ROLLBACK_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
    cfn_update
    ;;
  *)
    echo "Unexpected stack status: ${status}. Resolve in the console or delete the stack, then re-run."
    exit 1
    ;;
esac

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

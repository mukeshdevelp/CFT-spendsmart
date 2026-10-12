#!/usr/bin/env bash
# Local infra deploy (no Harbor / no Helm — use Jenkinsfile.helm or scripts/helm/ after stack is up).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_NAME="${CFN_STACK_NAME:-spendsmart-dev}"
REGION="${AWS_REGION:-us-east-1}"
TEMPLATE="${PACKAGED_TEMPLATE:-${ROOT}/packaged.yml}"
PARAMS_FILE="${ROOT}/.cfn-parameters.local.json"

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
    DOES_NOT_EXIST) return 0 ;;
    DELETE_IN_PROGRESS)
      echo "Stack ${STACK_NAME} is deleting; waiting for DELETE_COMPLETE..."
      aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
      return 0
      ;;
    DELETE_FAILED)
      echo "Stack ${STACK_NAME} is DELETE_FAILED (often S3 DataBucket not empty)."
      exit 1
      ;;
    CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS|UPDATE_COMPLETE_CLEANUP_IN_PROGRESS|\
    UPDATE_ROLLBACK_IN_PROGRESS|ROLLBACK_IN_PROGRESS|REVIEW_IN_PROGRESS)
      echo "Stack ${STACK_NAME} is busy (${status}); wait and re-run."
      exit 1
      ;;
    *) return 0 ;;
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
  DOES_NOT_EXIST) cfn_create ;;
  CREATE_COMPLETE|UPDATE_COMPLETE|ROLLBACK_COMPLETE|UPDATE_ROLLBACK_COMPLETE) cfn_update ;;
  *)
    echo "Unexpected stack status: ${status}"
    exit 1
    ;;
esac

echo "Stack ${STACK_NAME} deployed."
eval "$(bash "${ROOT}/scripts/cfn-alb-urls.sh")" && {
  echo "ALB_DNS=${ALB_DNS}"
  echo "Frontend=${FRONTEND_URL} Backend=${BACKEND_URL} Keycloak=${KEYCLOAK_URL}"
  echo "Next: Jenkinsfile.helm or bash scripts/helm/run-on-bastion-via-ssm.sh"
}

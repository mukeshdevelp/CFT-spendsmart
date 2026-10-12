#!/usr/bin/env bash
# Empty app data bucket and delete root stack (ROLLBACK_FAILED / DELETE_FAILED on S3 nested stack).
set -euo pipefail
STACK="${CFN_STACK_NAME:-spendsmart-dev}"
REGION="${AWS_REGION:-us-east-1}"
BUCKET="${S3_BUCKET_NAME:-athena-results-spendsmart-dev}"

STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo DOES_NOT_EXIST)
echo "Stack ${STACK} status: ${STATUS}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Emptying s3://${BUCKET} (required before stack delete)..."
  aws s3 rm "s3://${BUCKET}" --recursive --region "$REGION" || true
fi

case "$STATUS" in
  DOES_NOT_EXIST) echo "Nothing to delete."; exit 0 ;;
  DELETE_IN_PROGRESS)
    aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION"
    exit 0
    ;;
esac

echo "Deleting stack ${STACK}..."
aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION"
aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION" || {
  echo "Delete failed — check S3 bucket, CUR report, or orphan IAM roles."
  echo "  NAME_PREFIX=spendsmart-dev bash scripts/cfn-cleanup-orphan-eks-roles.sh"
  exit 1
}
echo "Stack deleted."

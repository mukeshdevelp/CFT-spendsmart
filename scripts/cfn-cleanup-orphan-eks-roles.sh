#!/usr/bin/env bash
# Remove IAM roles left after a rolled-back spendsmart-dev stack (blocks Eks nested stack recreate).
# Usage: NAME_PREFIX=spendsmart-dev bash scripts/cfn-cleanup-orphan-eks-roles.sh
set -euo pipefail
PREFIX="${NAME_PREFIX:-spendsmart-dev}"

detach_and_delete_role() {
  local role="$1"
  if ! aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    echo "skip (not found): $role"
    return 0
  fi
  echo "Cleaning role: $role"
  mapfile -t attached < <(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | tr '\t' '\n')
  for arn in "${attached[@]}"; do
    [[ -n "$arn" ]] && aws iam detach-role-policy --role-name "$role" --policy-arn "$arn"
  done
  mapfile -t inline < <(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | tr '\t' '\n')
  for p in "${inline[@]}"; do
    [[ -n "$p" ]] && aws iam delete-role-policy --role-name "$role" --policy-name "$p"
  done
  aws iam delete-role --role-name "$role"
  echo "deleted: $role"
}

for role in \
  "${PREFIX}-eks-cluster" \
  "${PREFIX}-eks-nodes" \
  "${PREFIX}-aws-load-balancer-controller-role"; do
  detach_and_delete_role "$role" || echo "WARN: could not delete $role (check console)"
done

echo "Done. Re-run package + cfn-deploy.sh"

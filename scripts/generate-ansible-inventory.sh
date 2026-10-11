#!/usr/bin/env bash
# Write ansible/inventory/jenkins-generated.yml from CloudFormation bastion output.
set -euo pipefail
CFN_STACK_NAME="${CFN_STACK_NAME:?}"
AWS_REGION="${AWS_REGION:?}"
OUT="${1:-ansible/inventory/jenkins-generated.yml}"
BASTION_USER="${BASTION_SSH_USER:-ec2-user}"

BASTION_IP="$(aws cloudformation describe-stacks \
  --stack-name "$CFN_STACK_NAME" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BastionPublicIp'].OutputValue" \
  --output text)"

if [ -z "$BASTION_IP" ] || [ "$BASTION_IP" = "None" ]; then
  echo "BastionPublicIp missing from stack $CFN_STACK_NAME (is Bastion enabled?)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
cat >"$OUT" <<EOF
---
all:
  children:
    bastion:
      hosts:
        spendsmart-bastion:
          ansible_host: ${BASTION_IP}
          ansible_user: ${BASTION_USER}
          kubeconfig_path: /home/${BASTION_USER}/.kube/config
EOF
echo "Wrote ${OUT} (bastion ${BASTION_IP})"

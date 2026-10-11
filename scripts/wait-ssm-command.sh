#!/usr/bin/env bash
# Usage: wait-ssm-command.sh <command-id> <instance-id> <region>
set -euo pipefail
CMD_ID="${1:?}"
INSTANCE_ID="${2:?}"
REGION="${3:?}"
for _ in $(seq 1 120); do
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --region "$REGION" --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in
    Success)
      aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
        --region "$REGION" --query StandardOutputContent --output text
      exit 0
      ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
        --region "$REGION" --query '[StandardOutputContent,StandardErrorContent]' --output text
      exit 1
      ;;
  esac
  sleep 5
done
echo "SSM command timed out: $CMD_ID"
exit 1

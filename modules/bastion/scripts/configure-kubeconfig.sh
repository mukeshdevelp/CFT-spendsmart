#!/bin/bash
# Write kubeconfig for ec2-user (and root). Requires EKS_REGION and EKS_CLUSTER_NAME.
set -euo pipefail
: "${EKS_REGION:?}"
: "${EKS_CLUSTER_NAME:?}"

mkdir -p /home/ec2-user/.kube /root/.kube
aws eks update-kubeconfig \
  --region "$EKS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube
chmod 600 /home/ec2-user/.kube/config
cp /home/ec2-user/.kube/config /root/.kube/config
chmod 600 /root/.kube/config

if ! grep -q KUBECONFIG /home/ec2-user/.bashrc 2>/dev/null; then
  echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/ec2-user/.bashrc
fi
if ! grep -q 'alias k=kubectl' /home/ec2-user/.bashrc 2>/dev/null; then
  echo 'alias k=kubectl' >> /home/ec2-user/.bashrc
fi

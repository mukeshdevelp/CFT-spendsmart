#!/bin/bash
# Run on the bastion (as root or with sudo) when UserData failed before kubectl/DB install.
# Default: cluster spendsmart in us-east-1. Override with EKS_REGION / EKS_CLUSTER_NAME.

set -euo pipefail

EKS_REGION="${EKS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-spendsmart}"
KUBECTL_VERSION="${KUBECTL_VERSION:-1.36.2}"
CFN_STACK_NAME="${CFN_STACK_NAME:-}"
LOG=/var/log/spendsmart-cluster-bootstrap.log

exec > >(tee -a "$LOG") 2>&1

echo "=== bastion-recover-bootstrap $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

dnf install -y aws-cfn-bootstrap python3
command -v curl >/dev/null || dnf install -y curl-minimal

curl -fL -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client

mkdir -p /home/ec2-user/.kube
aws eks update-kubeconfig \
  --region "$EKS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube
chmod 600 /home/ec2-user/.kube/config

grep -q KUBECONFIG /home/ec2-user/.bashrc 2>/dev/null || \
  echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/ec2-user/.bashrc
grep -q 'alias k=kubectl' /home/ec2-user/.bashrc 2>/dev/null || \
  echo 'alias k=kubectl' >> /home/ec2-user/.bashrc

export KUBECONFIG=/home/ec2-user/.kube/config
until kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for EKS API access..."
  sleep 10
done
kubectl get nodes -o wide

echo "If DB StatefulSets are missing, re-run the bootstrap from CloudFormation UserData"
echo "or update the stack after packaging the fixed bastion template (no curl in dnf install)."

if [[ -n "$CFN_STACK_NAME" ]]; then
  /opt/aws/bin/cfn-signal -e 0 \
    --stack "$CFN_STACK_NAME" \
    --resource ClusterBootstrap \
    --region "$EKS_REGION" \
    --reason "manual recover: kubectl configured"
  echo "Signaled ClusterBootstrap success on stack $CFN_STACK_NAME"
else
  echo "Set CFN_STACK_NAME=spendsmart-dev-Bastion-XXXX to signal CloudFormation when DB bootstrap is done."
fi

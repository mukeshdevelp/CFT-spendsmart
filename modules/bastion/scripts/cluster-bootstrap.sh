#!/bin/bash
# Installs kubectl, configures kubeconfig, labels nodes, deploys in-cluster DBs.
# Required env: EKS_REGION, EKS_CLUSTER_NAME, POSTGRES_SECRET_NAME, CLICKHOUSE_SECRET_NAME
# Optional: KUBECTL_VERSION (default 1.36.2), MANIFESTS_DIR (default /opt/spendsmart/manifests)

set -euo pipefail

LOG="${LOG:-/var/log/spendsmart-cluster-bootstrap.log}"
exec >>"$LOG" 2>&1

echo "=== cluster-bootstrap $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

: "${EKS_REGION:?}"
: "${EKS_CLUSTER_NAME:?}"
: "${POSTGRES_SECRET_NAME:?}"
: "${CLICKHOUSE_SECRET_NAME:?}"

KUBECTL_VERSION="${KUBECTL_VERSION:-1.36.2}"
MANIFESTS_DIR="${MANIFESTS_DIR:-/opt/spendsmart/manifests}"

dnf install -y aws-cfn-bootstrap python3
command -v curl >/dev/null || dnf install -y curl-minimal

if ! command -v kubectl >/dev/null; then
  curl -fL -o /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

mkdir -p /home/ec2-user/.kube /root/.kube
aws eks update-kubeconfig \
  --region "$EKS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube
chmod 600 /home/ec2-user/.kube/config
cp /home/ec2-user/.kube/config /root/.kube/config
chmod 600 /root/.kube/config

grep -q KUBECONFIG /home/ec2-user/.bashrc 2>/dev/null || \
  echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/ec2-user/.bashrc
grep -q 'alias k=kubectl' /home/ec2-user/.bashrc 2>/dev/null || \
  echo 'alias k=kubectl' >> /home/ec2-user/.bashrc

export KUBECONFIG=/root/.kube/config

until kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for EKS API..."
  sleep 10
done

for _ in $(seq 1 90); do
  count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  if [ "$count" -ge 4 ]; then break; fi
  sleep 20
done
kubectl wait --for=condition=Ready node --all --timeout=900s

mapfile -t APP_NODES < <(kubectl get nodes -l spendsmart.io/role=app -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
mapfile -t DATA_NODES < <(kubectl get nodes -l spendsmart.io/role=data -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
test "${#APP_NODES[@]}" -ge 2
test "${#DATA_NODES[@]}" -ge 1
kubectl label node "${APP_NODES[0]}" spendsmart.io/workload=backend --overwrite
kubectl label node "${APP_NODES[1]}" spendsmart.io/workload=frontend --overwrite
kubectl label node "${DATA_NODES[0]}" spendsmart.io/workload=database --overwrite

PGPASS=$(aws secretsmanager get-secret-value --secret-id "$POSTGRES_SECRET_NAME" --region "$EKS_REGION" \
  --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
CHPASS=$(aws secretsmanager get-secret-value --secret-id "$CLICKHOUSE_SECRET_NAME" --region "$EKS_REGION" \
  --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')

kubectl create namespace databases --dry-run=client -o yaml | kubectl apply -f -
kubectl -n databases create secret generic postgres-auth \
  --from-literal=username=dbadmin --from-literal=password="$PGPASS" --from-literal=database=cloudsentry \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n databases create secret generic clickhouse-auth \
  --from-literal=username=default --from-literal=password="$CHPASS" --from-literal=database=spendsmart \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${MANIFESTS_DIR}/databases.yaml"
kubectl -n databases rollout status statefulset/postgres --timeout=900s
kubectl -n databases rollout status statefulset/clickhouse --timeout=900s
kubectl -n databases get pods -o wide

echo "=== cluster-bootstrap complete ==="

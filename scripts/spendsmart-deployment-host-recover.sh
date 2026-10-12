#!/bin/bash
# Re-run SpendSmart Helm deploy on the DeploymentHost EC2 (after broken UserData / cloud-init error).
# Run as root on the deployment instance (SSM session). Sends CFN success signal when done.
#
# Optional env (auto-detected when unset):
#   ROOT_STACK_NAME   default spendsmart-dev
#   AWS_REGION        default us-east-1
#   EKS_CLUSTER_NAME  default spendsmart
#   NAME_PREFIX       default spendsmart-dev

set -euo pipefail

LOG=/var/log/spendsmart-helm-install.log
exec >>"$LOG" 2>&1

ROOT_STACK="${ROOT_STACK_NAME:-spendsmart-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER="${EKS_CLUSTER_NAME:-spendsmart}"
NAME_PREFIX="${NAME_PREFIX:-spendsmart-dev}"
NAMESPACE="${NAMESPACE:-spendsmart}"
CHART_REPO="${CHART_REPO:-https://github.com/OT-CONTAINER-KIT/helm-charts.git}"
CHART_BRANCH="${CHART_BRANCH:-feature/spendsmart-helm-chart}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-spendsmart-keycloak-admin}"

NESTED_ARN=$(aws cloudformation describe-stack-resource \
  --stack-name "$ROOT_STACK" \
  --logical-resource-id SpendSmart \
  --region "$AWS_REGION" \
  --query 'StackResourceDetail.PhysicalResourceId' \
  --output text)
CFN_STACK=$(echo "$NESTED_ARN" | sed 's|.*/stack/||' | cut -d/ -f1)

ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name "$ROOT_STACK" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue | [0]" \
  --output text)

signal_cfn() {
  /opt/aws/bin/cfn-signal -e "$1" --stack "$CFN_STACK" --resource DeploymentHost --region "$AWS_REGION" --reason "$2"
}
on_error() {
  signal_cfn 1 "Recover failed at line $1: $(tail -c 3800 "$LOG")"
}
trap 'on_error $LINENO' ERR

echo "=== spendsmart-deployment-host-recover $(date -u +%Y-%m-%dT%H:%M:%SZ) stack=$CFN_STACK alb=$ALB_DNS ==="

dnf install -y git tar gzip aws-cfn-bootstrap python3
command -v curl >/dev/null || dnf install -y curl-minimal
command -v helm >/dev/null || {
  curl -fsSL https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz -o /tmp/helm.tar.gz
  tar -xzf /tmp/helm.tar.gz -C /tmp && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
}

cluster_version=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" --query 'cluster.version' --output text)
curl -fsSL "https://dl.k8s.io/release/v${cluster_version}.0/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod 0755 /usr/local/bin/kubectl
export KUBECONFIG=/root/.kube/config
mkdir -p /root/.kube
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION" --kubeconfig "$KUBECONFIG"

kubectl wait --for=condition=Ready node --all --timeout=900s
kubectl -n databases wait --for=condition=Ready pod -l app=clickhouse --timeout=900s

CH_JSON=$(aws secretsmanager get-secret-value --secret-id "${NAME_PREFIX}/clickhouse" --region "$AWS_REGION" --query SecretString --output text)
CHPASS=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["password"])' "$CH_JSON")
CHUSER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["username"])' "$CH_JSON")
CHDB=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["database"])' "$CH_JSON")
GPG_KEY=$(aws secretsmanager get-secret-value --secret-id "${NAME_PREFIX}/spendsmart-encryption-key" --region "$AWS_REGION" \
  --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["GPG_KEY"])')

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<CHSVC
apiVersion: v1
kind: Service
metadata:
  name: clickhouse
  namespace: ${NAMESPACE}
spec:
  type: ExternalName
  externalName: clickhouse.databases.svc.cluster.local
CHSVC

if aws secretsmanager get-secret-value --secret-id "${NAME_PREFIX}/harbor-pull" --region "$AWS_REGION" >/dev/null 2>&1; then
  HARBOR_JSON=$(aws secretsmanager get-secret-value --secret-id "${NAME_PREFIX}/harbor-pull" --region "$AWS_REGION" --query SecretString --output text)
  HUSER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["username"])' "$HARBOR_JSON")
  HPASS=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["password"])' "$HARBOR_JSON")
  HSERVER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["server"])' "$HARBOR_JSON")
  kubectl -n "$NAMESPACE" create secret docker-registry harbor-ldc-coe-regcred \
    --docker-server="$HSERVER" \
    --docker-username="$HUSER" \
    --docker-password="$HPASS" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

kubectl -n "$NAMESPACE" create secret generic encryption-key \
  --from-literal=GPG_KEY="$GPG_KEY" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic clickhouse \
  --from-literal=CLICKHOUSE_HOST=clickhouse \
  --from-literal=CLICKHOUSE_PORT=8123 \
  --from-literal=CLICKHOUSE_USER="$CHUSER" \
  --from-literal=CLICKHOUSE_PASSWORD="$CHPASS" \
  --from-literal=CLICKHOUSE_DATABASE="$CHDB" \
  --from-literal=CLICKHOUSE_TABLE=service_costs \
  --from-literal=CLICKHOUSE_TLS=false \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic clickhouse-db \
  --from-literal=CLICKHOUSE_HOST=clickhouse \
  --from-literal=CLICKHOUSE_PORT=8123 \
  --from-literal=CLICKHOUSE_USER="$CHUSER" \
  --from-literal=CLICKHOUSE_PASSWORD="$CHPASS" \
  --from-literal=CLICKHOUSE_DATABASE="$CHDB" \
  --from-literal=CLICKHOUSE_TABLE=service_costs \
  --dry-run=client -o yaml | kubectl apply -f -

API_URL="http://${ALB_DNS}:8081"
KC_URL="http://${ALB_DNS}:8083"
cat >/tmp/client-a-values.yaml <<EOF
imagePullSecrets:
  - name: harbor-ldc-coe-regcred
backend:
  enabled: true
  image:
    repository: harbor.ldc.opstree.dev/coe/uniteconpro-backend-prod
    tag: latest
  nodeSelector:
    spendsmart.io/workload: backend
  service:
    type: NodePort
  annotations: {}
frontend:
  enabled: true
  image:
    repository: harbor.ldc.opstree.dev/coe/uniteconpro-frontend-prod
    tag: latest
  nodeSelector:
    spendsmart.io/workload: frontend
  service:
    type: NodePort
  configMap:
    name: uniteconpro-frontend
    data:
      VITE_API_BASE_URL: "${API_URL}"
      VITE_CLOUD_SENTRY_API_BASE_URL: ""
      VITE_KEYCLOAK_CLIENT_ID: spendsmart-frontend
      VITE_KEYCLOAK_REALM: spendsmart
      VITE_KEYCLOAK_URL: "${KC_URL}"
  nginx:
    enabled: true
    configMap:
      name: spendsmart-frontend-nginx
  annotations: {}
cloudsentry:
  enabled: false
engine:
  enabled: true
  image:
    repository: harbor.ldc.opstree.dev/coe/uniteconpro-engine-dev
    tag: latest
  schedule: "5 11,23 * * *"
  nodeSelector:
    spendsmart.io/workload: backend
EOF

kubectl apply -f - <<KEYCLOAK
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      nodeSelector:
        spendsmart.io/workload: frontend
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:latest
          args: ["start-dev"]
          env:
            - name: KEYCLOAK_ADMIN
              value: admin
            - name: KEYCLOAK_ADMIN_PASSWORD
              value: "${KEYCLOAK_ADMIN_PASSWORD}"
            - name: KC_HTTP_PORT
              value: "8080"
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: keycloak
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      nodePort: 30083
KEYCLOAK
kubectl -n "$NAMESPACE" rollout status deployment/keycloak --timeout=900s

rm -rf /opt/helm-charts
git clone --depth 1 --branch "$CHART_BRANCH" "$CHART_REPO" /opt/helm-charts
helm upgrade --install spendsmart /opt/helm-charts/charts/spendsmart \
  --namespace "$NAMESPACE" \
  --values /tmp/client-a-values.yaml \
  --wait --timeout 30m

patch_np() {
  local svc="$1" np="$2" port="$3" target="$4"
  kubectl patch svc "$svc" -n "$NAMESPACE" --type merge \
    -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":$port,\"targetPort\":$target,\"nodePort\":$np,\"protocol\":\"TCP\"}]}}"
}
patch_np spendsmart-frontend 30080 80 80
patch_np spendsmart-backend 30081 80 8000

kubectl -n "$NAMESPACE" get deploy,svc,pods
signal_cfn 0 "SpendSmart recovered via spendsmart-deployment-host-recover.sh"
echo "=== recover complete ==="

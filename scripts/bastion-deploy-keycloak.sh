#!/usr/bin/env bash
# Deploy in-cluster Keycloak (dev mode) in the SpendSmart namespace — same as modules/spendsmart CFN path.
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"

NAMESPACE="${NAMESPACE:-spendsmart}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
if [ -n "${SECRETS_JSON:-}" ] && [ -f "$SECRETS_JSON" ]; then
  KEYCLOAK_ADMIN="$(python3 -c "import json; c=json.load(open('${SECRETS_JSON}')); print(c.get('keycloak_admin') or 'admin')")"
  KEYCLOAK_ADMIN_PASSWORD="$(python3 -c "import json; c=json.load(open('${SECRETS_JSON}')); print(c.get('keycloak_admin_password') or '')")"
fi
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD required (Jenkins credential or secrets JSON)}"
KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-quay.io/keycloak/keycloak:25.0}"
KEYCLOAK_NODE_SELECTOR="${KEYCLOAK_NODE_SELECTOR:-spendsmart.io/workload=frontend}"
CONFIGURE_REALM="${CONFIGURE_REALM:-true}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-spendsmart}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-spendsmart-frontend}"
FRONTEND_BASE_URL="${FRONTEND_BASE_URL:-}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
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
          image: ${KEYCLOAK_IMAGE}
          args: ["start-dev"]
          env:
            - name: KEYCLOAK_ADMIN
              value: "${KEYCLOAK_ADMIN}"
            - name: KEYCLOAK_ADMIN_PASSWORD
              value: "${KEYCLOAK_ADMIN_PASSWORD}"
            - name: KC_HTTP_PORT
              value: "8080"
            - name: KC_HOSTNAME_STRICT
              value: "false"
            - name: KC_HTTP_ENABLED
              value: "true"
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /realms/master
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              memory: 1536Mi
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  selector:
    app: keycloak
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF

kubectl -n "$NAMESPACE" rollout status deployment/keycloak --timeout=900s
kubectl -n "$NAMESPACE" get deploy/keycloak svc/keycloak

if [ "$CONFIGURE_REALM" = "true" ]; then
  REALM_SCRIPT="${KEYCLOAK_REALM_SCRIPT:-$(dirname "$0")/bastion-configure-keycloak-realm.sh}"
  export KEYCLOAK_NAMESPACE="$NAMESPACE"
  export KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD KEYCLOAK_REALM KEYCLOAK_CLIENT_ID FRONTEND_BASE_URL
  bash "$REALM_SCRIPT"
fi

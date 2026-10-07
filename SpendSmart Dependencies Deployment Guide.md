# SpendSmart: Deploying Everything the Helm Chart Does Not Manage

The chart deploys only Backend, Frontend, Cloud-Sentry and the Engine CronJob. This guide covers everything else, in the order it must be built. Examples assume **AWS + EKS**. Replace `<placeholders>`. Never commit real credentials to Git.

## Order of work

| # | Phase | Why it comes here |
| --- | --- | --- |
| 0 | Prerequisites and decisions | Avoid rework |
| 1 | Network + EKS cluster | Everything runs on it |
| 2 | Ingress controller, DNS, TLS | Needed by Harbor, Keycloak and the app |
| 3 | Harbor (image registry) | Images must exist before the chart runs |
| 4 | PostgreSQL | Used by Cloud-Sentry (and Keycloak) |
| 5 | ClickHouse | Used by Backend and Engine |
| 6 | Keycloak | Used by Frontend login |
| 7 | AWS IAM for Cloud-Sentry and Engine | Cost data access |
| 8 | OpenTelemetry | Optional, but chart expects the injection resources |
| 9 | Create the 8 Kubernetes Secrets | Must exist before pods start |
| 10 | Deploy the chart |  |
| 11 | Validate |  |

---

## Phase 0: Prerequisites and decisions

Install: `aws` CLI, `kubectl`, `helm` (3.x), `eksctl` (or use CloudFormation), `jq`, `docker`, `psql`.

Decide and write down for each client/environment:

- Region, AWS account ID, namespace names (for example `spendsmart-dev`, `spendsmart-prod`)
- Domain names: `spendsmart.<domain>`, `spendsmart-api.<domain>`, `cloud-sentry.<domain>`, `keycloak.<domain>`, `harbor.<domain>`
- Where each dependency lives:
  - **PostgreSQL:** RDS (recommended) or in-cluster
  - **ClickHouse:** ClickHouse Cloud, in-cluster operator, or client-managed
  - **Keycloak:** new or the client's existing one (if existing, skip Phase 6 except client setup)
  - **Harbor:** new or existing (or use ECR instead)

> Tip: use one cluster per environment (DEV, PROD) or at least separate namespaces and separate Secrets.

---

## Phase 1: Network and EKS cluster

**Option A: eksctl (fastest)**

```bash
eksctl create cluster \
  --name spendsmart-dev \
  --region <region> \
  --version <supported-k8s-version> \
  --nodegroup-name workers \
  --node-type t3.large --nodes 3 --nodes-min 2 --nodes-max 5 \
  --managed --with-oidc
```

`--with-oidc` enables IAM Roles for Service Accounts (IRSA), which Phases 2 and 7 use.

**Option B: CloudFormation.** Define the VPC (public and private subnets, NAT), `AWS::EKS::Cluster`, `AWS::EKS::Nodegroup`, and an OIDC provider, then deploy:

```bash
aws cloudformation deploy --template-file eks.yaml --stack-name spendsmart-eks \
  --capabilities CAPABILITY_NAMED_IAM
```

Connect and verify:

```bash
aws eks update-kubeconfig --name spendsmart-dev --region <region>
kubectl get nodes
```

Install the EBS CSI driver add-on (required for any in-cluster database or Harbor volumes):

```bash
eksctl create addon --name aws-ebs-csi-driver --cluster spendsmart-dev
```

---

## Phase 2: Ingress controller, DNS and TLS

**2.1 AWS Load Balancer Controller**

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
# Create the IAM policy + IRSA service account first (see AWS docs: "Install AWS Load Balancer Controller with Helm")
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=spendsmart-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

**2.2 TLS.** Choose one:

- **ACM certificate** (attach to the ALB with the annotation `alb.ingress.kubernetes.io/certificate-arn`), or
- **cert-manager + Let's Encrypt** (also needed for OpenTelemetry in Phase 8):

```bash
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set crds.enabled=true
```

**2.3 DNS.** Create Route 53 records (or the client's DNS) pointing each hostname to the load balancer. Optionally install `external-dns` to automate this.

> The chart does **not** create Ingress. You must create Ingress resources that route the frontend, backend and Cloud-Sentry hostnames to their Services (check service names and ports with `kubectl get svc -n <ns>` after Phase 10).

---

## Phase 3: Harbor (private image registry)

Skip this if using an existing Harbor or ECR (with ECR you can drop `harbor-ldc-coe-regcred` and let node roles pull).

```bash
helm repo add harbor https://helm.goharbor.io && helm repo update
helm install harbor harbor/harbor -n harbor --create-namespace \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core=harbor.<domain> \
  --set externalURL=https://harbor.<domain> \
  --set harborAdminPassword='<from-secret-manager>' \
  --set persistence.persistentVolumeClaim.registry.size=100Gi
```

Then:

1. Log in to `https://harbor.<domain>` and create a project (for example `ldc-coe`).
2. Create a **robot account** with pull access (and push for CI).
3. Push the four images:

```bash
docker login harbor.<domain>
docker tag spendsmart-backend:<tag> harbor.<domain>/ldc-coe/spendsmart-backend:<tag>
docker push harbor.<domain>/ldc-coe/spendsmart-backend:<tag>
# repeat for frontend, cloud-sentry, engine
```

4. Create the pull secret (done in Phase 9).

---

## Phase 4: PostgreSQL (for Cloud-Sentry)

**Recommended: Amazon RDS** (private subnets; security group allows port 5432 only from the EKS node/pod security group).

```bash
aws rds create-db-instance \
  --db-instance-identifier spendsmart-pg \
  --engine postgres --db-instance-class db.t3.medium \
  --allocated-storage 50 --storage-encrypted \
  --master-username dbadmin --manage-master-user-password \
  --db-subnet-group-name <subnet-group> \
  --vpc-security-group-ids <sg-id> \
  --no-publicly-accessible
```

Create the application database and user (run from a pod or bastion inside the VPC):

```bash
psql -h <rds-endpoint> -U dbadmin -d postgres <<'SQL'
CREATE DATABASE cloudsentry;
CREATE USER cloudsentry_app WITH PASSWORD '<generated>';
GRANT ALL PRIVILEGES ON DATABASE cloudsentry TO cloudsentry_app;
SQL
```

Record: host, port 5432, database, user, password. These become the `postgres-config` Secret.

> Check with the application team whether Cloud-Sentry creates its own tables (migrations) or needs a schema script run first.

---

## Phase 5: ClickHouse (for Backend and Engine)

Pick one option.

**Option A: ClickHouse Cloud or client-managed.** Just collect host, port, database, user, password, TLS setting, and confirm network reachability from the cluster.

**Option B: In-cluster with the Altinity operator**

```bash
kubectl create namespace clickhouse
kubectl apply -n clickhouse -f \
  https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
```

```yaml
# clickhouse.yaml
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: spendsmart
  namespace: clickhouse
spec:
  configuration:
    clusters:
      - name: main
        layout: { shardsCount: 1, replicasCount: 1 }
  defaults:
    templates:
      dataVolumeClaimTemplate: data
  templates:
    volumeClaimTemplates:
      - name: data
        spec:
          accessModes: [ReadWriteOnce]
          resources: { requests: { storage: 100Gi } }
```

```bash
kubectl apply -f clickhouse.yaml
kubectl get pods -n clickhouse
```

**Then, in either case:**

1. Create the database, a user for the Backend (read-focused) and a user for the Engine (write access).
2. Create the **table the Engine writes to** (`CLICKHOUSE_TABLE`). **Get the exact schema/DDL from the application team.** It is not in the handoff document.
3. Test connectivity from a temporary pod in the target namespace.

Record host, port, database, user, password, table, TLS flag. These become the `clickhouse` and `clickhouse-db` Secrets.

---

## Phase 6: Keycloak (authentication)

Skip install if the client already has Keycloak. You still must do **6.2**.

**6.1 Install (official Keycloak Operator)**

```bash
kubectl create namespace keycloak
# Install CRDs and operator per the Keycloak docs for your chosen version:
# https://www.keycloak.org/operator/installation
```

```yaml
# keycloak.yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: keycloak
  namespace: keycloak
spec:
  instances: 2
  db:
    vendor: postgres
    host: <rds-endpoint>
    database: keycloak
    usernameSecret: { name: keycloak-db, key: username }
    passwordSecret: { name: keycloak-db, key: password }
  http:
    tlsSecret: <tls-secret>
  hostname:
    hostname: keycloak.<domain>
```

Keycloak needs its own database (create a `keycloak` DB and user on the RDS instance, using the same method as Phase 4).

**6.2 Configure the realm and client** (Admin console):

1. Create a **realm** (for example `spendsmart`).
2. Create a **client**. Use the Client ID you will put in `VITE_KEYCLOAK_CLIENT_ID`.
   - Client type: OpenID Connect, **public** client (browser SPA), Standard flow on, PKCE (S256) recommended.
   - **Valid redirect URIs:** `https://spendsmart.<domain>/*`
   - **Web origins:** `https://spendsmart.<domain>`
3. Create roles, groups and users as the application requires (confirm with the app team).

---

## Phase 7: AWS access for Cloud-Sentry and the Engine

1. Get the **exact IAM permission list** from the application team (this depends on which AWS services Cloud-Sentry and the Engine read). Do not guess.
2. Create IAM roles with least privilege and check SCPs in the client account.
3. Preferred: attach roles to Kubernetes service accounts using **IRSA or EKS Pod Identity** instead of static keys:

```bash
eksctl create iamserviceaccount \
  --cluster spendsmart-dev --namespace <ns> \
  --name <engine-serviceaccount> \
  --attach-policy-arn arn:aws:iam::<account>:policy/<engine-policy> \
  --approve
```

4. **Engine caveat from the handoff document:** the chart gives `aws-access` only to Cloud-Sentry. The Engine must get AWS access through its service account role (as above). Set the service account names in your values file so they match.
5. If you must use static keys for Cloud-Sentry, they go in the `aws-access` Secret (Phase 9).

---

## Phase 8: OpenTelemetry (optional, platform team)

The chart keeps the injection annotations, so if you use them, the operator and an `Instrumentation` resource must exist.

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  -n opentelemetry-operator-system --create-namespace \
  --set admissionWebhooks.certManager.enabled=true
```

Then create an `OpenTelemetryCollector` and an `Instrumentation` resource in the app namespace, matching the annotation values the chart uses (check `charts/spendsmart/values.yaml`). If you are not using OTEL, remove the annotations through values overrides so pods do not wait on a missing resource.

---

## Phase 9: Create the 8 Kubernetes Secrets

Create the namespace and Secrets **before** Helm. Load values from your secret manager into environment variables, not into files in Git.

```bash
export NS=spendsmart-dev
kubectl create namespace $NS

# 1. Backend -> ClickHouse
kubectl create secret generic clickhouse -n $NS \
  --from-literal=CLICKHOUSE_HOST="$CH_HOST" \
  --from-literal=CLICKHOUSE_PORT="$CH_PORT" \
  --from-literal=CLICKHOUSE_DATABASE="$CH_DB" \
  --from-literal=CLICKHOUSE_USER="$CH_USER" \
  --from-literal=CLICKHOUSE_PASSWORD="$CH_PASSWORD" \
  --from-literal=CLICKHOUSE_TLS="$CH_TLS"

# 2. Engine -> ClickHouse
kubectl create secret generic clickhouse-db -n $NS \
  --from-literal=CLICKHOUSE_HOST="$CH_HOST" \
  --from-literal=CLICKHOUSE_DATABASE="$CH_DB" \
  --from-literal=CLICKHOUSE_USER="$CH_ENGINE_USER" \
  --from-literal=CLICKHOUSE_PASSWORD="$CH_ENGINE_PASSWORD" \
  --from-literal=CLICKHOUSE_TABLE="$CH_TABLE"

# 3. Encryption key (Backend + Engine)
kubectl create secret generic encryption-key -n $NS \
  --from-literal=ENCRYPTION_MASTER_KEY="$ENC_KEY"

# 4. Cloud-Sentry -> PostgreSQL
kubectl create secret generic postgres-config -n $NS \
  --from-literal=POSTGRES_HOST="$PG_HOST" \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_DB=cloudsentry \
  --from-literal=POSTGRES_USER="$PG_USER" \
  --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD"

# 5. Cloud-Sentry -> AWS
kubectl create secret generic aws-access -n $NS \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_KEY" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET" \
  --from-literal=AWS_DEFAULT_REGION="$AWS_REGION"

# 6. Gemini
kubectl create secret generic gemini-key -n $NS \
  --from-literal=GEMINI_API_KEY="$GEMINI_KEY"

# 7. UnitEconPro base URL
kubectl create secret generic base-url -n $NS \
  --from-literal=UNITECONPRO_API_BASE_URL="$UEP_URL"

# 8. Harbor pull secret
kubectl create secret docker-registry harbor-ldc-coe-regcred -n $NS \
  --docker-server=harbor.<domain> \
  --docker-username="$HARBOR_ROBOT_USER" \
  --docker-password="$HARBOR_ROBOT_TOKEN"
```

Verify key names without printing values:

```bash
kubectl get secrets -n $NS
for s in clickhouse clickhouse-db postgres-config aws-access; do
  echo "== $s"; kubectl get secret $s -n $NS -o json | jq -r '.data | keys[]'
done
```

> For production, sync these from AWS Secrets Manager with the **External Secrets Operator** so they are never typed on a terminal.

---

## Phase 10: Deploy the application chart

```bash
cd <repo-root>
helm lint charts/spendsmart
helm template spendsmart charts/spendsmart -f client-a-dev-values.yaml   # review output

helm upgrade --install spendsmart charts/spendsmart \
  --namespace $NS \
  -f client-a-dev-values.yaml \
  --wait
```

Make sure the values file has:

- the four approved image tags
- the five `VITE_*` values (API URL, Cloud-Sentry URL, Keycloak URL/realm/client ID)
- `frontend.nginx.csp.connectSrc` including the Keycloak and Cloud-Sentry URLs
- `engine.schedule`
- service account names that match Phase 7

Then create the **Ingress** resources (Phase 2) for the three public hostnames.

---

## Phase 11: Validate

```bash
kubectl get deploy,svc,pods,cronjob,jobs -n $NS
kubectl port-forward svc/<backend-service> 8000:80 -n $NS &
curl -i http://127.0.0.1:8000/api/v1/healthz
curl -i http://127.0.0.1:8000/api/v1/readyz
curl -s http://127.0.0.1:8000/api/v1/dashboard/summary

# Force an Engine run and read the result
kubectl create job --from=cronjob/<engine-cronjob> engine-manual-1 -n $NS
kubectl logs job/engine-manual-1 -n $NS
```

Also confirm: frontend loads over HTTPS, Keycloak login redirects back correctly, Cloud-Sentry health responds, and dashboards show data after the Engine finishes.

---

## Troubleshooting quick table

| Symptom | Likely cause |
| --- | --- |
| `ImagePullBackOff` | Wrong Harbor path or tag, or `harbor-ldc-coe-regcred` missing or wrong |
| `CreateContainerConfigError` | A required Secret or key is missing in the namespace |
| Backend `readyz` fails | ClickHouse unreachable, wrong port or TLS flag, or bad credentials |
| Cloud-Sentry crash loop | PostgreSQL unreachable or security group blocks port 5432 |
| Login loop or "invalid redirect URI" | Keycloak redirect URIs or web origins do not match the frontend URL |
| Browser console CSP errors | `connectSrc` missing the Keycloak or API host |
| Engine job fails on AWS calls | Engine service account has no IAM role (aws-access is not injected into it) |

## Final checklist

- [ ] EKS, add-ons and ingress controller running
- [ ] DNS and TLS working for all hostnames
- [ ] Harbor up, images pushed, pull secret created
- [ ] PostgreSQL reachable, DB and user created
- [ ] ClickHouse reachable, DB, users and Engine table created
- [ ] Keycloak realm and client configured (redirect URIs and web origins)
- [ ] IAM roles attached for Cloud-Sentry and **Engine**
- [ ] OTEL ready, or annotations disabled
- [ ] All 8 Secrets present with correct keys
- [ ] Helm deploy succeeded and validation passed
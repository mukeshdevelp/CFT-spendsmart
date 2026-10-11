# SpendSmart Helm deployment (Jenkins + EKS bastion)

This guide deploys the [OT-CONTAINER-KIT spendsmart Helm chart](https://github.com/OT-CONTAINER-KIT/helm-charts/tree/feature/spendsmart-helm-chart/charts/spendsmart) onto the EKS cluster created by `main.yml`. The Jenkins pipeline is **`Jenkinsfile.helm`**. It does **not** use `helm-main.yml` CloudFormation; Helm runs on the bastion via SSM.

For a local Minikube walkthrough (different ClickHouse layout), see [spendsmart-deployment-local-repo](https://github.com/mukeshdevelp/spendsmart-deployment-local-repo).

## Architecture

```text
Jenkins agent
    │  AWS creds, Harbor creds, app secret creds
    │  build secrets JSON + rendered values.yaml
    ▼
S3 (transient) + SSM Run Command
    ▼
Bastion (ec2-user, kubeconfig)
    │  kubectl apply secrets
    │  Keycloak Deployment + realm/client bootstrap
    │  git clone chart branch → helm upgrade --install
    ▼
EKS namespace spendsmart
    Keycloak / Backend / Frontend / Engine (CronJob)
         │
         └── ClickHouse + Postgres in namespace databases (from bastion bootstrap)
```

## Prerequisites

1. **Infra stack** `CREATE_COMPLETE` or `UPDATE_COMPLETE` (`Jenkinsfile` or console), with bastion enabled.
2. **Bastion bootstrap finished**: at least 4 nodes, Postgres and ClickHouse pods `Running` in `databases`.
3. **S3 bucket** (`CFN_TEMPLATE_BUCKET`) with `bastion-assets/` synced (`scripts/sync-bastion-assets.sh` — the pipeline runs this).
4. **Jenkins** with AWS, Harbor, and optional Secret credentials (see below).
5. **Jenkins agent**: `aws`, `python3`, PyYAML (`pip install pyyaml` if `import yaml` fails), `git` not required on agent (Helm runs on bastion).
6. **Bastion IAM**: can read Secrets Manager `{NamePrefix}/postgres` and `{NamePrefix}/clickhouse` (same as cluster bootstrap).

## Jenkins job setup

1. Create a **Pipeline** job (or multibranch) pointing at this repo.
2. Set **Pipeline script path** to `Jenkinsfile.helm`.
3. Run **`Jenkinsfile`** (infra) first, then this job.

### Pipeline parameters (defaults)

Aligned with **`Jenkinsfile`** (infra), **`parameters.json`**, and **`client-a-values.yaml`**.

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `AWS_REGION` | `us-east-1` (first choice) | Same as infra deploy |
| `CFN_STACK_NAME` | `spendsmart-dev` | Infra stack |
| `CFN_TEMPLATE_BUCKET` | `spendsmart-cfn-packages` | Package/bastion bucket (same as `aws cloudformation package --s3-bucket …`) |
| `NAME_PREFIX` | `spendsmart-dev` | Secrets Manager: `spendsmart-dev/postgres`, `spendsmart-dev/clickhouse` |
| `K8S_NAMESPACE` | `spendsmart` | Helm namespace |
| `CHART_REPO` / `CHART_BRANCH` | OT-CONTAINER-KIT / `feature/spendsmart-helm-chart` | Chart source |
| `HELM_RELEASE` | `spendsmart` | Helm release name |
| `HELM_TIMEOUT` | `25m` | `helm upgrade --timeout` |
| `CLICKHOUSE_TABLE` | `service_costs` | Engine `clickhouse-db` secret |
| `KEYCLOAK_BROWSER_URL` | *(empty)* | Browser `VITE_KEYCLOAK_URL`; empty → in-cluster Service URL |
| `KEYCLOAK_URL` | `auto` | `http://keycloak.<namespace>.svc.cluster.local:8080` when browser URL empty |
| `KEYCLOAK_REALM` / `KEYCLOAK_CLIENT_ID` | `spendsmart` / `spendsmart-frontend` | Match `client-a-values.yaml` |
| `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_IMAGE` | `admin` / `quay.io/keycloak/keycloak:25.0` | Keycloak deploy |
| `DEPLOY_KEYCLOAK` / `CONFIGURE_KEYCLOAK_REALM` | `true` / `true` | Keycloak + realm bootstrap |
| `INSTALL_ALB_CONTROLLER` | `false` | One-time ALB controller Helm install |
| `SKIP_HELM_WAIT` | `false` | Skip `helm --wait` |
| `APPLY_CLOUDSENTRY_SECRETS` | `false` | Set `true` only when binding optional Cloud-Sentry creds |
| `HARBOR_DOCKER_SERVER` | `harbor.ldc.opstree.dev` | Harbor registry |
| `CREDENTIAL_*` | `aws-creds`, `harbor-creds`, `spendsmart-encryption-key`, `spendsmart-keycloak-admin`, … | Jenkins credential IDs |

Non-secret Helm overrides live in **`client-a-values.yaml`** in this repo (image repos, node selectors, `cloudsentry.enabled: false`, etc.). At deploy time, `scripts/prepare-helm-values.py` replaces placeholders with the stack **`AlbDnsName`** and `KEYCLOAK_URL`.

## Jenkins credentials to create

Store secrets in Jenkins (**Manage Jenkins → Credentials**). Use **IDs** that match pipeline parameters (or override the parameter to your IDs).

| Credential ID (default param) | Type | Used for |
|-------------------------------|------|----------|
| `aws-creds` (`CREDENTIAL_AWS`) | AWS credentials | S3, SSM, Secrets Manager on Jenkins agent |
| `harbor-creds` (`CREDENTIAL_HARBOR`) | Username with password | `harbor-ldc-coe-regcred` image-pull secret |
| `spendsmart-encryption-key` (`CREDENTIAL_ENCRYPTION_KEY`) | Secret text | K8s `encryption-key` → `ENCRYPTION_KEY` |
| `spendsmart-keycloak-admin` (`CREDENTIAL_KEYCLOAK_ADMIN`) | Secret text | Keycloak `KEYCLOAK_ADMIN_PASSWORD` (user via `KEYCLOAK_ADMIN_USER`, default `admin`) |
| `spendsmart-gemini-key` (`CREDENTIAL_GEMINI_KEY`) | Secret text (optional) | `gemini-key` if Cloud-Sentry enabled later |
| `spendsmart-base-url` (`CREDENTIAL_BASE_URL`) | Secret text (optional) | `base-url` for Cloud-Sentry |
| `spendsmart-app-aws` (`CREDENTIAL_APP_AWS`) | Username with password (optional) | K8s `aws-access` (app IAM keys, not Jenkins AWS) |

**Harbor** username is typically a robot account or user; password is the robot secret. Registry host is set by `HARBOR_DOCKER_SERVER` (default `harbor.ldc.opstree.dev`).

**Encryption key** must match what the application team expects. The chart reads secret `encryption-key` with key `ENCRYPTION_KEY`.

Do **not** put passwords in `client-a-values.yaml` or commit them to Git.

## Kubernetes secrets created by the pipeline

The bastion runs `scripts/bastion-apply-chart-secrets.sh` with JSON built by `scripts/build-runtime-secrets-json.py`:

| Secret name | Keys / purpose |
|-------------|----------------|
| `harbor-ldc-coe-regcred` | Docker registry pull (Harbor) |
| `encryption-key` | `ENCRYPTION_KEY` |
| `clickhouse` | Backend: host `clickhouse.databases.svc.cluster.local`, port `9000`, user `default`, DB `spendsmart` |
| `clickhouse-db` | Engine: same + `CLICKHOUSE_TABLE` (default `service_costs`) |
| `postgres-config` | Cloud-Sentry: `postgres.databases.svc.cluster.local`, user `dbadmin`, DB `cloudsentry` |
| `gemini-key`, `base-url`, `aws-access` | Only if matching Jenkins credentials are configured |

DB passwords come from **AWS Secrets Manager** (`{NamePrefix}/postgres`, `{NamePrefix}/clickhouse`), not from Jenkins.

## ConfigMap (frontend)

The chart creates frontend ConfigMaps from **`client-a-values.yaml`** → `frontend.configMap.data` and nginx CSP lists. The pipeline sets:

- `VITE_API_BASE_URL` → `http://<AlbDnsName>` from CloudFormation
- `VITE_KEYCLOAK_URL` → `KEYCLOAK_URL` parameter
- `VITE_CLOUD_SENTRY_API_BASE_URL` → empty unless you set env `CLOUDSENTRY_URL` on the Jenkins agent before build (optional)

To change image tags or schedules, edit `client-a-values.yaml` and re-run the pipeline.

## Pipeline stages (summary)

1. **Preflight** — infra stack and S3 bucket.
2. **Sync bastion helper scripts** — uploads `bastion-apply-chart-secrets.sh`, `bastion-helm-install.sh`, etc.
3. **Wait for nodes and database pods** — SSM checks on bastion.
4. **Prepare Helm values** — `prepare-helm-values.py` → archived `helm-values-rendered.yaml`.
5. **Build runtime secrets JSON** — Harbor, encryption, Keycloak admin password from Jenkins; DB passwords from Secrets Manager.
6. **Install ALB controller** (optional) — Helm on bastion.
7. **Apply secrets, Keycloak, Helm release** — S3 → bastion → chart secrets → `bastion-deploy-keycloak.sh` (optional realm bootstrap) → `helm upgrade --install`.

Keycloak runs `quay.io/keycloak/keycloak:25.0` with `start-dev` on the **frontend** node (`spendsmart.io/workload: frontend`), same as the legacy `modules/spendsmart` stack. Realm bootstrap uses the stack **AlbDnsName** as `FRONTEND_BASE_URL` for redirect URIs and web origins so browser login against the in-cluster Keycloak URL works from the public ALB frontend.

## Manual verification (bastion or SSM)

```bash
export KUBECONFIG=/home/ec2-user/.kube/config
kubectl get nodes
kubectl get pods -n databases
kubectl get secrets -n spendsmart
kubectl get deploy,svc,pods,cronjob -n spendsmart
kubectl get deploy,svc keycloak -n spendsmart
helm list -n spendsmart
```

Keycloak admin console (from bastion, after port-forward):

```bash
kubectl port-forward -n spendsmart svc/keycloak 8080:8080
# Open http://127.0.0.1:8080 — user KEYCLOAK_ADMIN_USER, password from Jenkins credential
```

Backend health (port-forward from bastion):

```bash
kubectl port-forward -n spendsmart svc/spendsmart-backend 8000:80
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/v1/healthz
```

Engine test job:

```bash
kubectl create job --from=cronjob/spendsmart-engine spendsmart-engine-test -n spendsmart
kubectl logs -n spendsmart job/spendsmart-engine-test -f
```

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| `ImagePullBackOff` | Harbor cred ID, robot permissions, `harbor-ldc-coe-regcred` in namespace |
| `CreateContainerConfigError` | Missing secret; `kubectl describe pod -n spendsmart` |
| Backend not ready | ClickHouse pod in `databases`, secret `clickhouse`, readiness `/api/v1/readyz` |
| SSM command failed | Jenkins console → SSM output; bastion `/var/log/spendsmart-cluster-bootstrap.log` |
| Helm clone fails | Bastion outbound HTTPS; `CHART_BRANCH` exists |
| Wrong API URL in UI | Stack output `AlbDnsName`, re-run pipeline; archived `helm-values-rendered.yaml` |

After infra changes, re-run **`scripts/sync-bastion-assets.sh`** (or the Helm Jenkins job, which syncs automatically).

## Local vs cloud ClickHouse

| | Local Minikube guide | This EKS deployment |
|--|----------------------|---------------------|
| ClickHouse host | `clickhouse` in `spendsmart` ns | `clickhouse.databases.svc.cluster.local` |
| Database / user | `cost` / `dba` | `spendsmart` / `default` |
| Deployed by | Manual YAML in guide | `cluster-bootstrap.sh` + `databases.yaml` |

## Ansible (alternative to Jenkins + bastion scripts)

Same deploy flow as **`kubernetes.core`** modules — no `bastion-helm-install.sh` required when using Ansible.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp group_vars/secrets.yml.example group_vars/secrets.yml
# edit inventory/hosts.yml and secrets.yml
ansible-playbook playbooks/deploy-spendsmart.yml
```

Details: [ansible/README.md](ansible/README.md).

## Related files

| File | Role |
|------|------|
| `Jenkinsfile.helm` | Pipeline definition |
| `client-a-values.yaml` | Non-secret Helm values |
| `scripts/prepare-helm-values.py` | Merge CFN outputs into values |
| `scripts/build-runtime-secrets-json.py` | Jenkins-side secrets bundle |
| `scripts/bastion-apply-chart-secrets.sh` | Apply secrets on cluster |
| `scripts/bastion-helm-install.sh` | `helm lint` + `helm upgrade --install` |
| `scripts/bastion-deploy-keycloak.sh` | Keycloak Deployment/Service + optional realm bootstrap |
| `scripts/bastion-configure-keycloak-realm.sh` | Admin API: realm + public client |
| `scripts/wait-ssm-command.sh` | Poll SSM command status |

## Rollback

On the bastion:

```bash
helm history spendsmart -n spendsmart
helm rollback spendsmart <REVISION> -n spendsmart --wait
```

Uninstall:

```bash
helm uninstall spendsmart -n spendsmart
```

Externally managed databases and Secrets Manager entries are not removed by Helm uninstall.

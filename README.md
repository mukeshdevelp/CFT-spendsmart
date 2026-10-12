# SpendSmart CloudFormation (infra)

**Pipeline 1 — Infra:** VPC, EKS, Secrets Manager (Postgres/ClickHouse), in-cluster DBs on bastion bootstrap, ALB (:8080/:8081/:8083), S3/CUR/Glue/Athena, IAM.

**Pipeline 2 — App:** [Jenkinsfile.helm](Jenkinsfile.helm) — Harbor → ECR (optional) + Helm on bastion via SSM. See [HELM-DEPLOY.md](HELM-DEPLOY.md).

| Doc | Purpose |
|-----|---------|
| [ONE_CLICK_DEPLOYMENT.md](ONE_CLICK_DEPLOYMENT.md) | Package, deploy infra, troubleshoot |
| [HELM-DEPLOY.md](HELM-DEPLOY.md) | ECR mirror + Helm deploy |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Modules and outputs |

## Quick start (infra)

```sh
bash scripts/sync-bastion-assets.sh <CFN_TEMPLATE_BUCKET> us-east-1

aws cloudformation package \
  --template-file main.yml \
  --s3-bucket <CFN_TEMPLATE_BUCKET> \
  --output-template-file packaged.yml \
  --region us-east-1

bash scripts/cfn-deploy.sh
```

Then **Jenkinsfile.helm** or mirror locally with `scripts/helm/mirror-harbor-to-ecr.sh` and `scripts/helm/run-on-bastion-via-ssm.sh`.

## Credentials and secrets

Nothing in git stores production passwords except **defaults** below. Random DB passwords live in **AWS Secrets Manager** after infra deploy.

### Keycloak (Helm deploy on bastion)

| Item | Default | Override |
|------|---------|----------|
| Admin console user | `admin` | — |
| Admin password | `spendsmart-keycloak-admin` | env `KEYCLOAK_ADMIN_PASSWORD` or Jenkins |
| Realm (frontend env) | `spendsmart` | set in generated Helm values |
| OIDC client id (frontend) | `spendsmart-frontend` | set in generated Helm values |
| URL | `http://<ALB_DNS>:8083` | from stack output `KeycloakUrl` |

Login: open **KeycloakUrl**, use **admin** / password above (`start-dev` image; not for production hardening).

### App secrets (namespace `spendsmart`, created by deploy script)

| Kubernetes secret | Source |
|-------------------|--------|
| `encryption-key` | **`GPG_KEY`** — you supply (Jenkins credential `spendsmart-gpg-key`; same as local backend `encryption-key`) |
| `clickhouse`, `clickhouse-db` | User/password/db from Secrets Manager `{NamePrefix}/clickhouse` |
| Harbor pull | Not used when images come from **ECR** (default) |

### Databases (Secrets Manager + in-cluster `databases` ns)

| Secret id | Username | Database | Password |
|-----------|----------|----------|----------|
| `{NamePrefix}/postgres` | `dbadmin` | `cloudsentry` | **Auto-generated** (32 chars) on stack create |
| `{NamePrefix}/clickhouse` | `dba` | `cost` | **Auto-generated** (32 chars) on stack create |

Retrieve (example `NamePrefix=spendsmart-dev`, `us-east-1`):

```sh
aws secretsmanager get-secret-value --secret-id spendsmart-dev/postgres --region us-east-1 \
  --query SecretString --output text | python3 -m json.tool
aws secretsmanager get-secret-value --secret-id spendsmart-dev/clickhouse --region us-east-1 \
  --query SecretString --output text | python3 -m json.tool
```

Bastion bootstrap copies these into `databases` namespace secrets `postgres-auth` / `clickhouse-auth` for the StatefulSets.

### Harbor / ECR

| Item | Where |
|------|--------|
| Harbor robot user + token | Your machine or Jenkins `harbor-creds` — only for **mirror** to ECR |
| ECR image pull | EKS node IAM — no password in cluster |

### URLs after deploy

```sh
eval "$(bash scripts/cfn-alb-urls.sh)"   # FRONTEND_URL, BACKEND_URL, KEYCLOAK_URL
```

---

## How `client-a-values.yaml` is created

There is **no committed `client-a-file.yml`** in this repo. On each Helm deploy, **`scripts/helm/deploy-spendsmart-on-bastion.sh`** writes **`/tmp/client-a-values.yaml`** on the bastion and passes it to Helm:

```sh
helm upgrade --install spendsmart ... --values /tmp/client-a-values.yaml
```

**How that file is built:**

1. **ALB DNS** — from env `ALB_DNS` (Jenkins/SSM sets it from CloudFormation `AlbDnsName`) or stack lookup.
2. **API / Keycloak URLs** — `VITE_API_BASE_URL=http://<ALB>:8081`, `VITE_KEYCLOAK_URL=http://<ALB>:8083`.
3. **Images** — ECR repos `spendsmart/backend|frontend|engine` and tag `IMAGE_TAG` (default `latest`).
4. **Node selectors** — `spendsmart.io/workload: backend|frontend` (must match bastion bootstrap labels).
5. **Engine** — CronJob image + schedule `5 11,23 * * *`.

Keycloak itself is **not** in that YAML; the same script applies a separate manifest (Deployment + NodePort **30083**) with admin password above, then installs the OT-CONTAINER-KIT **spendsmart** chart from branch `feature/spendsmart-helm-chart`.

To inspect after a deploy (on bastion): `sudo grep -A2 client-a /var/log/spendsmart-helm-deploy.log` or re-read the heredoc in `deploy-spendsmart-on-bastion.sh`.

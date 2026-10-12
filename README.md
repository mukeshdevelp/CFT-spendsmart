# SpendSmart CloudFormation (infra)

**Pipeline 1 — Infra:** VPC, EKS, Secrets Manager (Postgres/ClickHouse), in-cluster DBs on bastion bootstrap, ALB (:8080/:8081/:8083), S3/CUR/Glue/Athena, IAM.

**Pipeline 2 — App:** [Jenkinsfile.helm](Jenkinsfile.helm) or [HELM-DEPLOY.md](HELM-DEPLOY.md) (Helm chart + Keycloak on bastion via SSM).

| Doc | Purpose |
|-----|---------|
| [ONE_CLICK_DEPLOYMENT.md](ONE_CLICK_DEPLOYMENT.md) | Package, deploy infra, troubleshoot |
| [HELM-DEPLOY.md](HELM-DEPLOY.md) | Helm one-click after infra |
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

Then run **Jenkinsfile.helm** (credentials `harbor-creds`, `spendsmart-gpg-key`) or `scripts/helm/run-on-bastion-via-ssm.sh`.

## DB credentials (Secrets Manager)

| Secret | User | Database |
|--------|------|----------|
| `{NamePrefix}/postgres` | `dbadmin` | `cloudsentry` |
| `{NamePrefix}/clickhouse` | `dba` | `cost` |

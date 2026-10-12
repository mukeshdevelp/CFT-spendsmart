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

## DB credentials (Secrets Manager)

| Secret | User | Database |
|--------|------|----------|
| `{NamePrefix}/postgres` | `dbadmin` | `cloudsentry` |
| `{NamePrefix}/clickhouse` | `dba` | `cost` |

# SpendSmart CloudFormation

Single-path deploy: **`main.yml`** (VPC, EKS, databases, ALB, bastion bootstrap, **SpendSmart** Helm app).

| Doc | Purpose |
|-----|---------|
| [ONE_CLICK_DEPLOYMENT.md](ONE_CLICK_DEPLOYMENT.md) | Package, deploy, troubleshoot |
| [CLOUDFORMATION-SPENDSMART.md](CLOUDFORMATION-SPENDSMART.md) | App module, Harbor, URLs :8080 / :8081 / :8083 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module boundaries and outputs |

## Quick start

```sh
bash scripts/sync-bastion-assets.sh <CFN_TEMPLATE_BUCKET> us-east-1
cp deploy/harbor.env.example deploy/harbor.env   # set HARBOR_PASSWORD (gitignored)

aws cloudformation package \
  --template-file main.yml \
  --s3-bucket <CFN_TEMPLATE_BUCKET> \
  --output-template-file packaged.yml \
  --region us-east-1

bash scripts/cfn-deploy-with-harbor.sh
# prints ALB_DNS + Frontend/Backend/Keycloak URLs from stack outputs
```

Or use Jenkins **`Jenkinsfile`** with credential **`harbor-creds`** (Harbor docker login).

**Match local Minikube `spendsmart` ns:** `bash scripts/export-spendsmart-cluster-spec.sh` → `deploy/spendsmart-cluster-spec.json`

## DB credentials (Secrets Manager)

| Secret | User | Database |
|--------|------|----------|
| `{NamePrefix}/postgres` | `dbadmin` | `cloudsentry` |
| `{NamePrefix}/clickhouse` | `dba` | `cost` |

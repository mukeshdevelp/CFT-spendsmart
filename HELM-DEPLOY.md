# SpendSmart Helm deploy (after infra)

Infra stack (`Jenkinsfile` / `scripts/cfn-deploy.sh`) must be **CREATE_COMPLETE** with:

- `databases` namespace: Postgres + ClickHouse Running (bastion bootstrap)
- Node labels: `spendsmart.io/workload=backend|frontend|database`
- ALB listeners 8080 / 8081 / 8083 → NodePorts 30080 / 30081 / 30083

## Jenkins one-click

1. Create credentials:
   - **`harbor-creds`** — Harbor robot (same as `docker login harbor.ldc.opstree.dev`)
   - **`spendsmart-gpg-key`** — secret text = backend `GPG_KEY` (local `encryption-key` secret)
   - **`aws-creds`** — deploy account
2. Run pipeline **`Jenkinsfile.helm`** with `CFN_STACK_NAME=spendsmart-dev`.
3. Job uploads `deploy-spendsmart-on-bastion.sh` to S3 and runs it on the bastion via SSM.

Logs on bastion: `sudo tail -f /var/log/spendsmart-helm-deploy.log`

## Local / CLI

```bash
export AWS_REGION=us-east-1 CFN_STACK_NAME=spendsmart-dev CFN_TEMPLATE_BUCKET=spendsmart-cfn-packages
export HARBOR_USERNAME=... HARBOR_PASSWORD=... GPG_KEY=...

bash scripts/sync-bastion-assets.sh "$CFN_TEMPLATE_BUCKET" "$AWS_REGION"
bash scripts/helm/run-on-bastion-via-ssm.sh scripts/helm/deploy-spendsmart-on-bastion.sh
```

## URLs

```bash
eval "$(bash scripts/cfn-alb-urls.sh)"
# Frontend :8080  Backend :8081  Keycloak :8083
```

## Chart

- Repo: `https://github.com/OT-CONTAINER-KIT/helm-charts.git`
- Branch: `feature/spendsmart-helm-chart`
- Release: `spendsmart` in namespace **`spendsmart`**

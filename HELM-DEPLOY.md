# SpendSmart Helm deploy (after infra)

Infra (`Jenkinsfile` / `scripts/cfn-deploy.sh`) must be **CREATE_COMPLETE** with `databases` pods Ready and ALB :8080/:8081/:8083.

## One Jenkins job: `Jenkinsfile.helm`

1. **Mirror** (optional, default on): Harbor → ECR on the **same Jenkins agent** as the job (`docker` + `aws` CLI). Optional param **`MIRROR_AGENT_LABEL`** if only some nodes have Docker.
2. **Deploy**: bastion SSM → Helm (`spendsmart-gpg-key` + `aws-creds`)

| Parameter | Meaning |
|-----------|---------|
| `MIRROR_TO_ECR` | `false` if you already pushed from PC; `true` needs Docker on Jenkins agent |
| `MIRROR_AGENT_LABEL` | Optional node label (leave empty = default agent) |
| `IMAGE_TAG` | ECR tag for deploy; empty + mirror on → **`BUILD_NUMBER`** |
| `HARBOR_TAG` | Source tag on Harbor (default `latest`) |
| `ECR_REPO_PREFIX` | `spendsmart/backend`, `spendsmart/frontend`, `spendsmart/engine` |

Credentials: **`harbor-creds`** (mirror only), **`spendsmart-gpg-key`**, **`aws-creds`**.

Bastion log: `sudo tail -f /var/log/spendsmart-helm-deploy.log`

## Manual: PC mirror then deploy

```bash
export AWS_REGION=us-east-1
export HARBOR_USERNAME=... HARBOR_PASSWORD=...
export IMAGE_TAG=latest
bash scripts/helm/mirror-harbor-to-ecr.sh

export CFN_STACK_NAME=spendsmart-dev CFN_TEMPLATE_BUCKET=spendsmart-cfn-packages
export IMAGE_TAG=latest GPG_KEY=...
bash scripts/sync-bastion-assets.sh "$CFN_TEMPLATE_BUCKET" "$AWS_REGION"
bash scripts/helm/run-on-bastion-via-ssm.sh
```

Harbor sources (mirror script):

| ECR | Harbor |
|-----|--------|
| `spendsmart/backend` | `harbor.ldc.opstree.dev/coe/uniteconpro-backend-prod` |
| `spendsmart/frontend` | `harbor.ldc.opstree.dev/coe/uniteconpro-frontend-prod` |
| `spendsmart/engine` | `harbor.ldc.opstree.dev/coe/uniteconpro-engine-dev` |

## URLs

```bash
eval "$(bash scripts/cfn-alb-urls.sh)"
```

## Chart

`OT-CONTAINER-KIT/helm-charts` branch `feature/spendsmart-helm-chart`, release `spendsmart` in namespace **`spendsmart`**.

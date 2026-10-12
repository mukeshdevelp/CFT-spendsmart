# SpendSmart CloudFormation Architecture

## Purpose

Root stack **`main.yml`** provisions AWS infra through nested templates under **`modules/`**. Application Helm (frontend, backend, engine, Keycloak) is **not** in CloudFormation — use **`Jenkinsfile.helm`** ([HELM-DEPLOY.md](HELM-DEPLOY.md)).

## Module layout

| Template | Role |
|----------|------|
| `modules/network-skeleton` | VPC, subnets, IGW, NAT |
| `modules/eks` | EKS cluster, node groups, addons, ALB controller Pod Identity IAM |
| `modules/db` | Secrets Manager: `{prefix}/postgres`, `{prefix}/clickhouse` |
| `modules/bastion` | Bastion EC2, EKS access, S3 bootstrap assets → `databases` StatefulSets |
| `modules/alb` | Internet ALB :8080 / :8081 / :8083 → NodePorts 30080 / 30081 / 30083 |
| `modules/s3`, `glue`, `athena`, `iam` | Data lake + analytics + bastion role |

## Traffic

```text
Internet → ALB (CFN) → EC2 workers (NodePort) → spendsmart pods (Helm, post-infra)
```

Bastion bootstrap labels nodes (`spendsmart.io/workload=*`) and installs Postgres/ClickHouse in **`databases`**.

## Key outputs

| Output | Use |
|--------|-----|
| `AlbDnsName`, `FrontendUrl`, `BackendUrl`, `KeycloakUrl` | App URLs after Helm |
| `BastionInstanceId` | SSM / Helm deploy target |
| `EksClusterName`, `EksConfigureKubectl` | kubectl |
| Db / S3 / Glue / Athena / Analytics | Data plane |

## Lifecycle

1. `bash scripts/sync-bastion-assets.sh <bucket>` → package → `bash scripts/cfn-deploy.sh` (or `Jenkinsfile`).
2. Wait for bastion: `kubectl get po -n databases`.
3. `Jenkinsfile.helm` or `scripts/helm/run-on-bastion-via-ssm.sh`.

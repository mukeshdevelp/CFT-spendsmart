# Local Harbor guide → EKS Jenkins/Ansible pipeline

This maps the [local SpendSmart deploy guide](https://github.com/mukeshdevelp/spendsmart-deployment-local-repo) to **your EKS pipelines**. **Minikube and steps 7–11** (ClickHouse inside `spendsmart` ns, `cost` / `dba`) are **not** run in CI — ClickHouse is already provisioned by **infra** in namespace `databases`.

## What the app pipeline does

| Guide step | Local (Minikube) | EKS pipeline |
|------------|------------------|--------------|
| 2–3 Harbor login / `docker pull` | On your laptop | **Not needed** — EKS pulls images using `harbor-ldc-coe-regcred` |
| 5 Namespace `spendsmart` | `kubectl create ns` | Ansible / Helm `--create-namespace` |
| 6 `harbor-ldc-coe-regcred` | Jenkins `harbor-creds` → K8s secret | Same |
| 7–11 ClickHouse in `spendsmart` | Manual YAML | **Skip** — use `clickhouse.databases.svc.cluster.local` from bastion bootstrap |
| 12 Secret `clickhouse` (7 keys) | `dba` / `cost` / port `8123` | Same **keys**; password from SM; user `default`, DB `spendsmart`, host `clickhouse.databases.svc.cluster.local` |
| 13 Secret `clickhouse-db` (6 keys) | Engine | Same |
| 14 `encryption-key` | App team key | Jenkins `spendsmart-encryption-key` → `ENCRYPTION_KEY` |
| 15 Verify secrets | 4 secrets | Same four names only |
| 16 `client-a-values.yaml` | `client-a-file.yml` | Repo root `client-a-values.yaml` (Harbor images, `cloudsentry.enabled: false`, engine **dev** image) |
| 17–19 `helm lint` / `template` / `upgrade --install` | Local chart path | Chart from GitHub `feature/spendsmart-helm-chart` |

## Required Jenkins credentials (app job only)

| Credential | For |
|------------|-----|
| `harbor-creds` | Step 6 |
| `spendsmart-encryption-key` (optional) | Step 14 — or job param **ENCRYPTION_KEY_FALLBACK** (dev default) |
| `aws-creds` | Read `{name_prefix}/clickhouse` password from Secrets Manager |
| `bastion-ssh-key` | Ansible SSH to bastion (Ansible job only) |

## Required Kubernetes secrets in `spendsmart`

```
harbor-ldc-coe-regcred
encryption-key
clickhouse
clickhouse-db
```

## Images (from guide)

| Workload | Image |
|----------|--------|
| Backend | `harbor.ldc.opstree.dev/coe/uniteconpro-backend-prod:latest` |
| Frontend | `harbor.ldc.opstree.dev/coe/uniteconpro-frontend-prod:latest` |
| Engine | `harbor.ldc.opstree.dev/coe/uniteconpro-engine-dev:latest` |

## Pipelines to use

1. **`Jenkinsfile`** — infra only (no app).  
2. **`Jenkinsfile.ansible`** — app deploy (recommended): secrets + Helm.  
   Or **`Jenkinsfile.helm`** — same secrets via SSM + `bastion-helm-install.sh`.

Optional: set `inject_cfn_urls: true` in Ansible `group_vars/all.yml` to fill `VITE_API_BASE_URL` from ALB (not in local guide step 16).

## Post-deploy checks (guide 20–21)

On bastion:

```bash
export KUBECONFIG=/home/ec2-user/.kube/config
kubectl get pods,deploy,svc,cronjob -n spendsmart
kubectl logs -n spendsmart deploy/spendsmart-backend --tail=50
kubectl create job --from=cronjob/spendsmart-engine spendsmart-engine-test -n spendsmart
```

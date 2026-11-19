# SpendSmart — GCP single-VM deployment

Deploy SpendSmart on **one GCP VM** with **k3s**, in-cluster **Postgres** and **ClickHouse**, and the **Helm chart** in `charts/spendsmart`.

Quick start: see **[END_GOAL](END_GOAL)**.

```bash
cp deploy/harbor.env.example deploy/harbor.env
cp deploy/gpg.env.example deploy/gpg.env
bash scripts/vm/one-click-deploy.sh
```

## Repository layout

| Path | Purpose |
|------|---------|
| `charts/spendsmart/` | Application Helm chart (+ `values-vm.yaml`) |
| `kubernetes/vm/` | Database StatefulSets and app DB aliases |
| `scripts/vm/` | Install and deploy scripts |
| `deploy/*.env.example` | Local secrets (copy to gitignored `deploy/*.env`) |

## NodePorts

| Service | Port |
|---------|------|
| Frontend | 30080 |
| Backend API | 30081 |
| Cloud-Sentry (optional) | 30082 |
| Keycloak | 30083 |
# SpendSmart — Helm on existing Kubernetes (GCP VM)

Deploy on a server that **already has Kubernetes**. Databases are in-cluster (`kubernetes/vm/`); the app is installed via **Helm** only (no k3s installer).

See **[END_GOAL](END_GOAL)**.

```bash
# once: databases
bash scripts/vm/bootstrap-databases.sh

# app
cp deploy/gpg.env.example deploy/gpg.env
bash scripts/vm/one-click-deploy.sh
```

## Layout

| Path | Purpose |
|------|---------|
| `charts/spendsmart/` | Helm chart + `values-vm.yaml` |
| `kubernetes/vm/` | DB StatefulSets and DB service aliases |
| `scripts/vm/` | Bootstrap + Helm deploy |

## NodePorts

| Service | Port |
|---------|------|
| Frontend | 30080 |
| Backend API | 30081 |
| Cloud-Sentry (optional) | 30082 |
| Keycloak | 30083 |
# SpendSmart — CloudFormation only

Application deploy is **`modules/spendsmart`** nested in **`main.yml`** (parameter `DeploySpendSmart=true`).

## Flow

1. **`modules/db`** — Secrets Manager `{NamePrefix}/clickhouse` with `username`, `database`, generated `password`.
2. **`modules/bastion`** — bootstrap installs ClickHouse/Postgres in `databases` using that secret (`clickhouse-auth`).
3. **`modules/alb`** — one ALB, three listeners:
   - **8080** → NodePort **30080** (frontend)
   - **8081** → NodePort **30081** (backend `/api/v1/healthz`)
   - **8083** → NodePort **30083** (Keycloak)
4. **`modules/spendsmart`** — EC2 deployment host runs Helm chart (frontend + backend only; engine/cloudsentry off), Keycloak Deployment, K8s secrets from SM.

## Harbor (image pull)

Same credentials as:

```bash
docker login harbor.ldc.opstree.dev -u '<user>' -p '<token>'
```

CloudFormation stores them in Secrets Manager `{NamePrefix}/harbor-pull` and creates `harbor-ldc-coe-regcred` in `spendsmart`.

**Local deploy**

```bash
cp deploy/harbor.env.example deploy/harbor.env
# edit deploy/harbor.env — set HARBOR_PASSWORD (file is gitignored)
aws cloudformation package ...  # if needed
bash scripts/cfn-deploy-with-harbor.sh
```

**Jenkins infra job (`Jenkinsfile`)**

Create credential **`harbor-creds`** (Username with password): user `Mukesh_Sharma`, password = Harbor CLI token.  
Parameter **`CREDENTIAL_HARBOR`** defaults to `harbor-creds`; **`DEPLOY_SPENDSMART`** defaults to `true`.

## URLs (stack outputs)

| Output | Example |
|--------|---------|
| `SpendSmartFrontendUrl` | `http://<alb-dns>:8080` |
| `SpendSmartBackendUrl` | `http://<alb-dns>:8081` |
| `SpendSmartKeycloakUrl` | `http://<alb-dns>:8083` |

## Logs

On the deployment instance (private subnet, use SSM Session Manager):

```bash
sudo tail -f /var/log/spendsmart-helm-install.log
```

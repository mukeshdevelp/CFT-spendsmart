# Ansible: SpendSmart Helm deploy

Ansible equivalent of **`Jenkinsfile.helm`** + bastion scripts (`bastion-apply-chart-secrets.sh`, `bastion-deploy-keycloak.sh`, `bastion-configure-keycloak-realm.sh`, `bastion-helm-install.sh`). Helm is installed via **`kubernetes.core.helm`** — no deploy shell scripts required.

## Prerequisites

- Ansible 2.14+ on your laptop or CI runner
- AWS credentials on the control node (same as Jenkins `aws-creds`)
- SSH to the bastion (`inventory/hosts.yml`)
- Bastion: `kubectl`, kubeconfig at `/home/ec2-user/.kube/config`, outbound HTTPS for Helm chart git clone

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp group_vars/secrets.yml.example group_vars/secrets.yml
# edit secrets.yml — or use ansible-vault encrypt group_vars/secrets.yml
```

Edit **`inventory/hosts.yml`**: set `ansible_host` to the bastion public IP (or use AWS SSM connection plugin).

## Run

From the `ansible/` directory:

```bash
ansible-playbook playbooks/deploy-spendsmart.yml
```

With extra overrides:

```bash
ansible-playbook playbooks/deploy-spendsmart.yml \
  -e cfn_stack_name=spendsmart-dev \
  -e deploy_keycloak=true \
  -e install_alb_controller=false
```

## What the role does

| Step | Replaces |
|------|----------|
| Play 1 (localhost) | `prepare-helm-values.py` — CFN outputs + `client-a-values.yaml` placeholders |
| `preflight.yml` | Jenkins “Wait for nodes and database pods” |
| `secrets.yml` | `build-runtime-secrets-json.py` + `bastion-apply-chart-secrets.sh` |
| `keycloak.yml` | `bastion-deploy-keycloak.sh` |
| `keycloak_realm.yml` | `bastion-configure-keycloak-realm.sh` |
| `helm.yml` | `bastion-helm-install.sh` |
| `alb_controller.yml` | Jenkins optional ALB controller stage |

Defaults live in **`group_vars/all.yml`** (aligned with `Jenkinsfile.helm`).

## Secrets

| Source | Variables |
|--------|-----------|
| `group_vars/secrets.yml` | Harbor, `encryption_key`, `keycloak_admin_password` |
| AWS Secrets Manager | `{name_prefix}/clickhouse`, `{name_prefix}/postgres` (read on bastion) |

Do not commit `group_vars/secrets.yml`.

## Jenkins (recommended two-job setup)

1. **Job 1** — `Jenkinsfile` (CloudFormation infra)  
2. **Job 2** — `Jenkinsfile.ansible` (this playbook on the bastion)

Full steps, credentials, and optional auto-trigger: **[JENKINS-TWO-PIPELINES.md](JENKINS-TWO-PIPELINES.md)**.

See also [helm-deployment.md](../helm-deployment.md) for the Helm/SSM alternative (`Jenkinsfile.helm`).

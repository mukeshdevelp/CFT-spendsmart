# Jenkins: infra pipeline + Ansible app pipeline

Two separate Jenkins jobs deploy SpendSmart end-to-end. Today only **SpendSmart** (frontend, backend, engine, Keycloak) is automated; later you can add more playbooks/hosts for other servers.

## Overview

```text
Job 1: spendsmart-infra          Job 2: spendsmart-ansible-deploy
(Jenkinsfile)                    (Jenkinsfile.ansible)
        |                                  ^
        |  CloudFormation main.yml         |
        |  EKS, bastion, DB bootstrap      |
        +-------- CREATE_COMPLETE ---------+
                    (optional trigger)
```

| Job | Script path | Purpose |
|-----|-------------|---------|
| **Infra** | `Jenkinsfile` | Package/deploy `main.yml`, sync bastion assets |
| **App (SpendSmart)** | `Jenkinsfile.ansible` | Ansible `playbooks/deploy-spendsmart.yml` on bastion via SSH |

Alternative: **`Jenkinsfile.helm`** still works (SSM + shell on bastion). Use **either** Helm Jenkins **or** Ansible Jenkins for app deploy, not both in one run.

## 1. Create Jenkins jobs

### Job A — `spendsmart-infra` (or your existing name)

- **Pipeline** → Definition: Pipeline script from SCM  
- **Script Path:** `Jenkinsfile`  
- Credentials: `aws-creds`  
- Parameters: set `CFN_TEMPLATE_BUCKET`, etc. (defaults in Jenkinsfile)

### Job B — `spendsmart-ansible-deploy`

- **Script Path:** `Jenkinsfile.ansible`  
- Same repo branch as infra

**Jenkins agent requirements (Job B):**

- `ansible-playbook`, `python3`, PyYAML (`pip install pyyaml`)
- `aws` CLI (play 1 reads CloudFormation on the agent)
- Network: SSH **tcp/22** to bastion public IP
- Collections installed each build under `ansible/collections/`

## 2. Jenkins credentials (Job B)

| ID | Type | Purpose |
|----|------|---------|
| `aws-creds` | AWS | CFN + Secrets Manager (via Ansible on bastion) |
| `bastion-ssh-key` | SSH Username with private key | User `ec2-user`, private key for EC2 key pair `mukesh` (or your key) |
| `harbor-creds` | Username/password | Harbor pull secret |
| `spendsmart-encryption-key` | Secret text | App encryption key |
| `spendsmart-keycloak-admin` | Secret text | Keycloak admin password |

Optional (only if `APPLY_CLOUDSENTRY_SECRETS=true`): `spendsmart-gemini-key`, `spendsmart-base-url`, `spendsmart-app-aws`.

## 3. Run order

### Manual (recommended first time)

1. Run **infra** job → wait for `CREATE_COMPLETE` / `UPDATE_COMPLETE`.  
2. Wait until bastion bootstrap finishes (4 nodes, `databases` pods Running).  
3. Run **ansible deploy** job with same `CFN_STACK_NAME` and `AWS_REGION`.

### Automatic chain

On the **infra** job, enable parameter **`TRIGGER_ANSIBLE_DEPLOY`** and set **`ANSIBLE_DEPLOY_JOB_NAME`** to `spendsmart-ansible-deploy` (must match Job B name exactly).

After a successful infra build, Jenkins starts Job B with `AWS_REGION` and `CFN_STACK_NAME` passed through.

## 4. What Ansible does on the bastion

Play 1 runs on the **Jenkins agent** (localhost): read stack outputs, render Helm values from `client-a-values.yaml`.

Play 2 SSH to **bastion** (IP from `BastionPublicIp`):

1. Wait for cluster / DB pods (optional)  
2. Create K8s secrets (Harbor, ClickHouse, Postgres, encryption, Keycloak inputs)  
3. Deploy Keycloak + realm bootstrap  
4. `helm upgrade --install spendsmart` (OT-CONTAINER-KIT chart)

Frontend and backend run on **EKS worker nodes** (node selectors in `client-a-values.yaml`), not on separate VMs. The bastion is only the **deployment control host** with `kubectl`/`helm`. When you add “different servers” later, add Ansible groups/inventory and new playbooks; this job stays the SpendSmart/EKS path.

## 5. Local test (without Jenkins)

```bash
# On your laptop with AWS creds + SSH to bastion
export CFN_STACK_NAME=spendsmart-dev AWS_REGION=us-east-1
bash scripts/generate-ansible-inventory.sh ansible/inventory/jenkins-generated.yml
cp ansible/group_vars/secrets.yml.example ansible/group_vars/secrets.yml
# edit secrets.yml
cd ansible && ansible-galaxy collection install -r requirements.yml -p collections
ANSIBLE_COLLECTIONS_PATH=./collections ansible-playbook \
  -i inventory/jenkins-generated.yml playbooks/deploy-spendsmart.yml \
  --private-key ~/.ssh/mukesh.pem
```

## 6. Troubleshooting

| Issue | Check |
|-------|--------|
| SSH failed | Bastion SG allows Jenkins agent IP; key matches `ExistingEc2KeyName` |
| `BastionPublicIp` empty | Bastion enabled in stack; output exists |
| Ansible missing collections | Job stage “Install Ansible collections” |
| DB password errors | Bastion instance role can read `{name_prefix}/clickhouse` and `/postgres` |
| Helm timeout | Increase `HELM_TIMEOUT`; set `WAIT_FOR_CLUSTER=true` |

See also [README.md](README.md) and [../helm-deployment.md](../helm-deployment.md).

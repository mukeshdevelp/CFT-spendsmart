# Jenkins: infra + Ansible app deploy

See **[APP-PIPELINE-MAPPING.md](../APP-PIPELINE-MAPPING.md)** for how this matches the Harbor local guide (secrets + Helm only; no Minikube ClickHouse steps).

## Jobs

| Job | Script | Purpose |
|-----|--------|---------|
| Infra | `Jenkinsfile` | CloudFormation `main.yml` |
| App | `Jenkinsfile.ansible` | `playbooks/deploy-spendsmart.yml` on bastion |

## App job credentials

- `aws-creds`
- `bastion-ssh-key` (user `ec2-user`)
- `harbor-creds`
- `spendsmart-encryption-key`

## Run order

1. Infra job → `CREATE_COMPLETE`  
2. Wait for bastion bootstrap (4 nodes, `databases` pods Running)  
3. App job with same `CFN_STACK_NAME` / `AWS_REGION`

Optional: infra parameter **`TRIGGER_ANSIBLE_DEPLOY`** + job name **`spendsmart-ansible-deploy`**.

## Agent requirements (app job)

`ansible-playbook`, `python3`, `pyyaml`, `aws` CLI, SSH to bastion.

## Local test

```bash
export CFN_STACK_NAME=spendsmart-dev AWS_REGION=us-east-1
bash scripts/generate-ansible-inventory.sh ansible/inventory/jenkins-generated.yml
cp ansible/group_vars/secrets.yml.example ansible/group_vars/secrets.yml
# edit secrets.yml
cd ansible && ansible-galaxy collection install -r requirements.yml -p collections
ANSIBLE_COLLECTIONS_PATH=./collections ansible-playbook \
  -i inventory/jenkins-generated.yml playbooks/deploy-spendsmart.yml \
  --private-key ~/.ssh/your-key.pem
```

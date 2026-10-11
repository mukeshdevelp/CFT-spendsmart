# SpendSmart Ansible pipeline

Jenkins `Jenkinsfile.helm` drives these playbooks (localhost / AWS APIs).

## Prerequisites on Jenkins agent

- `ansible` and `ansible-galaxy`
- AWS credentials with CloudFormation, S3, SSM, EC2
- `aws` CLI (for `cloudformation package`)

```bash
ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections
export ANSIBLE_COLLECTIONS_PATH="$(pwd)/ansible/collections"
```

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `playbooks/preflight.yml` | Repo files and S3 bucket |
| `playbooks/infra.yml` | Parameters, assets, package `main.yml` |
| `playbooks/deploy_infra.yml` | Create/update infra stack |
| `playbooks/wait_infra.yml` | Wait for infra stack |
| `playbooks/wait_eks.yml` | SSM poll until EKS nodes ready |
| `playbooks/sync_bastion_assets.yml` | Upload bastion bootstrap files only |
| `playbooks/upload_values.yml` | Upload `client-a-values.yaml` |
| `playbooks/secrets.yml` | Runtime K8s secrets via bastion SSM |
| `playbooks/helm.yml` | Helm CFN parameters, package, deploy |
| `playbooks/wait_helm.yml` | Wait for Helm stack |

Runtime secrets are passed in `jenkins-runtime-secrets.json` (written by Jenkins from job parameters).

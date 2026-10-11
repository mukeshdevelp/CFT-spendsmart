# SpendSmart CloudFormation Deployment

This folder contains the modular CloudFormation deployment for SpendSmart. `main.yml` is the deployment entrypoint. Nested templates are under `modules/` and are uploaded with `aws cloudformation package`.

For deployment commands and troubleshooting, see [ONE_CLICK_DEPLOYMENT.md](ONE_CLICK_DEPLOYMENT.md). For ownership boundaries and outputs, see [ARCHITECTURE.md](ARCHITECTURE.md).

## What It Creates

- VPC, two public subnets, two private subnets in distinct AZs, internet gateway, and one NAT gateway/EIP when enabled.
- Bastion host (SSH/SSM). Cluster bootstrap (kubectl, node labels, in-cluster Postgres/ClickHouse) runs in the background via `spendsmart-cluster-bootstrap.service`; it does not block CloudFormation.
- Bastion IAM lives in `modules/iam`. UserData installs **kubectl** and **kubeconfig** for `ec2-user` from `install-kubectl.sh` / `configure-kubeconfig.sh` in `bastion-assets/`. Cluster bootstrap (labels, DB StatefulSets) runs via `spendsmart-cluster-bootstrap.service`. Publish assets with `scripts/sync-bastion-assets.sh` before deploy.
- Private EKS cluster and two managed node groups. Node group 2 is the data node (`c7i-flex.xlarge`, 100 GB) and runs PostgreSQL and ClickHouse as in-cluster StatefulSets.
- PostgreSQL service `postgres.databases.svc.cluster.local:5432` and ClickHouse service `clickhouse.databases.svc.cluster.local` on ports 8123 and 9000.

## Database login

| Database | Username | Password |
|---|---|---|
| PostgreSQL (`cloudsentry`) | `dbadmin` | Generated into Secrets Manager secret `spendsmart-dev/postgres` |
| ClickHouse (`spendsmart`) | `default` | Generated into Secrets Manager secret `spendsmart-dev/clickhouse` |

```sh
aws secretsmanager get-secret-value --secret-id spendsmart-dev/postgres --region us-east-1 --query SecretString --output text
aws secretsmanager get-secret-value --secret-id spendsmart-dev/clickhouse --region us-east-1 --query SecretString --output text
```
- AWS Load Balancer Controller IAM role and EKS Pod Identity association.
- S3 data/results bucket, Glue database and role, Athena workgroup, and analytics IAM role/policy.

The AWS Load Balancer Controller creates the application ALB and target group from a Kubernetes Ingress. There is intentionally no independent CloudFormation ALB target group: EKS managed node groups do not attach their changing Auto Scaling groups to an unrelated target group automatically.

## Application deployment (after infra)

`main.yml` stops at infrastructure: EKS nodes and in-cluster Postgres/ClickHouse (`databases` namespace) via bastion bootstrap. It does **not** install the SpendSmart Helm chart.

1. **Jenkins `Jenkinsfile`** — package and deploy `main.yml` (sync bastion assets first).
2. **Jenkins `Jenkinsfile.helm`** — wait for nodes/DB pods, apply runtime secrets (Harbor, etc.), deploy `helm-main.yml` (`modules/spendsmart`).

Harbor and optional app secrets are Jenkins job parameters; the spendsmart module still creates DB-related secrets in the `spendsmart` namespace from Secrets Manager.

## Deploy Infrastructure

From this directory, replace `<TEMPLATE_BUCKET>` with an existing bucket in the target account and region:

```sh
bash scripts/sync-bastion-assets.sh <TEMPLATE_BUCKET> us-east-1

aws cloudformation package \
  --template-file main.yml \
  --s3-bucket <TEMPLATE_BUCKET> \
  --output-template-file packaged.yml \
  --region us-east-1

aws cloudformation validate-template \
  --template-body file://packaged.yml \
  --region us-east-1

aws cloudformation create-stack \
  --stack-name spendsmart-dev \
  --template-body file://packaged.yml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

aws cloudformation wait stack-create-complete \
  --stack-name spendsmart-dev \
  --region us-east-1
```

Check stack events with:

```sh
aws cloudformation describe-stack-events \
  --stack-name spendsmart-dev \
  --region us-east-1
```

After setting up the namespace Secrets, package again and enable application installation:

```sh
aws cloudformation package --template-file main.yml --s3-bucket spendsmart-cfn-packages --output-template-file packaged.yml --region us-east-1 && aws cloudformation validate-template --template-body packaged.yml --region us-east-1 

aws cloudformation package --template-file main.yml --s3-bucket spendsmart-cfn-packages --output-template-file packaged.yml --region us-east-1 && aws cloudformation validate-template --template-body file://packaged.yml --region us-east-1


aws cloudformation deploy \
  --template-file packaged.yml \
  --stack-name spendsmart-dev \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM
```

Use the same region for the stack, template bucket, EC2 key pair, and AMI lookup. `BastionSshCidrs` is a comma-separated list. It currently includes `0.0.0.0/0`, which permits SSH from any IPv4 address and makes the `103.87.45.139/32` entry redundant; do not use this setting for production. Use a globally unique `S3BucketName`. The defaults create a NAT gateway and a private-only EKS endpoint; the NAT gateway, EKS control plane, EC2 nodes, optional bastion, optional deployment host, controller-managed ALB, and data transfer incur charges. CloudFormation deletes the S3 bucket during rollback or stack deletion; deletion can fail if the bucket contains objects or object versions.

I’ll submit a Service Quotas increase request for the `us-east-1` EC2 On-Demand Standard vCPU quota, from 8 to 25. AWS approval may be required, so I’ll check the request status after submitting it.

Ran terminal command:  aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-1216C47A --desired-value 25 --region us-east-1 --output json

AWS accepted the request for processing as `PENDING` with a desired limit of 25. I’m checking the request record once so I can report its current status and identifier accurately.

Ran terminal command:  aws service-quotas get-requested-service-quota-change --request-id 685efca09e8046dbb2f5472d04b09518kM1gTtNm --region us-east-1 --query 'RequestedQuota.{Id:Id,Quota:QuotaName,DesiredValue:DesiredValue,Status:Status,CaseId:CaseId,Created:Created}' --output table

I submitted the EC2 On-Demand Standard vCPU quota increase request for `us-east-1`, from 8 to 25 vCPUs. AWS shows it as **PENDING**, so the quota has not increased yet.

Request ID: `685efca09e8046dbb2f5472d04b09518kM1gTtNm`

aws s3api create-bucket --bucket spendsmart-cfn-packages-047078339928-us-east-1 --region us-east-1 --object-ownership BucketOwnerEnforced && aws s3api put-public-access-block --bucket spendsmart-cfn-packages-047078339928-us-east-1 --region us-east-1 --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true && aws s3api put-bucket-encryption --bucket spendsmart-cfn-packages-047078339928-us-east-1 --region us-east-1 --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' && aws s3api put-bucket-versioning --bucket spendsmart-cfn-packages-047078339928-us-east-1 --region us-east-1 --versioning-configuration Status=Enabled
# SpendSmart One-Click Deployment Guide

This guide deploys the modular CloudFormation root stack in `main.yml`. Its nested templates are under `modules/`; package them to S3 before deployment. SpendSmart Helm deployment is opt-in because its image-pull and application Secrets must already exist in EKS. See [ARCHITECTURE.md](ARCHITECTURE.md) for the module layout and stack outputs.

## What Gets Deployed

| Component | Created or managed by | Purpose |
|---|---|---|
| VPC, public/private subnets, routes, and one NAT gateway | CloudFormation | Network foundation and private-subnet outbound access |
| Optional bastion | CloudFormation | Administrative access to the private network |
| Private EKS cluster | CloudFormation | Kubernetes control plane |
| Two managed node groups | CloudFormation / EKS | Worker capacity; both can launch in either private subnet |
| EKS add-ons, including Pod Identity Agent | EKS | Cluster networking, DNS, service routing, and pod identity |
| Load Balancer Controller IAM role and Pod Identity association | CloudFormation / EKS | Grants the controller AWS permissions without static credentials |
| S3 bucket, Glue database/role, Athena workgroup, and analytics IAM resources | CloudFormation | Data storage, catalog/query, and analytics access |
| Application ALB (8080 / 8081 / 8083) | CloudFormation `modules/alb` | Frontend, backend, Keycloak listeners |
| SpendSmart app (Helm + Keycloak) | CloudFormation `modules/spendsmart` | When `DeploySpendSmart=true` and Harbor params set |

See [CLOUDFORMATION-SPENDSMART.md](CLOUDFORMATION-SPENDSMART.md) for Harbor and app URLs.

## Pre-requisites

| What you need | Why |
|---|---|
| Select the target AWS account and region. Commands below use `us-east-1`. | CloudFormation resources, EC2 key pairs, quotas, and AMI lookups are regional/account-specific. |
| AWS credentials authorized for CloudFormation, IAM, VPC/EC2, EKS and Pod Identity, S3, Glue, and Athena; acknowledge `CAPABILITY_NAMED_IAM`. | The stack creates named IAM roles and policies as well as network, compute, EKS, and data resources. |
| The EC2 key-pair name `mukesh` in `parameters.json`, spelled exactly as it exists in `us-east-1`. | The bastion and EKS node launch configuration use this key pair. |
| Set `BastionSshCidrs` in `parameters.json` as a comma-separated list of CIDRs. | Each value creates an SSH ingress rule. This configuration includes `0.0.0.0/0`, which opens SSH to every IPv4 address; the additional `/32` does not restrict that access. |
| Set `S3BucketName` to a globally unique bucket name. | S3 bucket names are unique across AWS accounts and Regions. |
| Verify that the selected EKS version, instance type, EKS/EC2/NAT quotas, and EKS Pod Identity are supported in the Region. | Unsupported versions, insufficient quotas, or unavailable capacity can prevent stack resources from being created. |
| Review `EksNodesEgressCidr`, which defaults to `0.0.0.0/0`. | Private nodes need outbound access through NAT to bootstrap and for the controller to call AWS APIs; production egress should be restricted with appropriate VPC endpoints and security-group rules. |
| Ensure the deployment operator can reach the private EKS API endpoint, using a connected VPC network, VPN, Direct Connect, or the bastion. | The EKS API endpoint is private-only by default, and `kubectl`/Helm need network access to it. |

**Cost and bucket deletion:** The NAT gateway, EKS control plane, EC2 nodes, bastion, ALB, and data transfer incur charges. CloudFormation deletes the S3 bucket on rollback or stack deletion. S3 requires a bucket to be empty, including all object versions, before it can be deleted; a non-empty bucket can make stack cleanup fail.

### S3 nested stack fails with “Validation failure detected”

Usually **`S3BucketName` (`athena-results-spendsmart-dev`) already exists** outside the stack, or **`spendsmart-cur`** CUR report already exists. Empty and delete the orphan bucket, or remove the old CUR definition in Billing → Cost & Usage Reports, then re-deploy. The stack creates the bucket with `DeletionPolicy: Delete` so rollback removes it when the bucket is empty (including all object versions).

## Console Deployment

1. From the `CFT` directory, package `main.yml` and its nested templates to an S3 bucket in the target region:

   ```sh
   bash scripts/sync-bastion-assets.sh <TEMPLATE_BUCKET> us-east-1
   aws cloudformation package \
     --template-file main.yml \
     --s3-bucket <TEMPLATE_BUCKET> \
     --output-template-file packaged.yml \
     --region us-east-1
   ```

2. Open CloudFormation in the target region and choose **Create stack**, then **With new resources (standard)**.
3. Upload `CFT/packaged.yml`.
4. Use stack name `spendsmart-dev`.
5. Review parameters. Confirm `Ec2KeyName`, `BastionSshCidrs`, and a unique `S3BucketName`.
6. Continue to **Review**, acknowledge IAM resource creation, then submit.
7. Wait for `CREATE_COMPLETE`. If it fails, open **Events** and inspect the earliest resource-level failure.
8. In **Outputs**, record `EksConfigureKubectl`, `AlbControllerRoleArn`, `AlbControllerNamespace`, `AlbControllerServiceAccountName`, `AlbControllerVersion`, and the data/analytics values you need.

## CLI Deployment

From the `CFT` directory, use AWS CLI v2. Edit the `S3BucketName` and `BastionSshCidrs` values in `parameters.json` first. `BastionSshCidrs` is a comma-separated `CommaDelimitedList` value. Replace `<TEMPLATE_BUCKET>` with an existing S3 bucket in the deployment region:

```sh
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

For updates, package `main.yml` again and use `aws cloudformation update-stack` with the packaged template, parameters, and capabilities. To inspect stack outputs:

```sh
aws cloudformation describe-stacks \
  --stack-name spendsmart-dev \
  --query 'Stacks[0].Outputs' \
  --output table \
  --region us-east-1
```

For a failed operation, inspect the earliest failed event:

```sh
aws cloudformation describe-stack-events \
  --stack-name spendsmart-dev \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[Timestamp,LogicalResourceId,ResourceStatusReason]' \
  --output table \
  --region us-east-1
```

## Deploy SpendSmart (same stack)

Set Harbor credentials (`deploy/harbor.env` or Jenkins `harbor-creds`). `parameters.json` defaults `DeploySpendSmart=true`.

```sh
bash scripts/cfn-deploy-with-harbor.sh
```

Stack outputs: `SpendSmartFrontendUrl` (:8080), `SpendSmartBackendUrl` (:8081), `SpendSmartKeycloakUrl` (:8083).

Deployment host logs (SSM): `sudo tail -f /var/log/spendsmart-helm-install.log`

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `InvalidClientTokenId`, `ExpiredToken`, or `AccessDenied` | Credentials are expired, point to another account, or lack permissions. | Reauthenticate, verify `aws sts get-caller-identity`, and check CloudFormation/IAM/EC2/EKS/Pod Identity/S3/Glue/Athena permissions. |
| `InsufficientCapabilitiesException` | Named IAM resources were not acknowledged. | Add `--capabilities CAPABILITY_NAMED_IAM` or acknowledge IAM resources in the Console. |
| EKS cluster creation fails | Unsupported EKS version, missing quota, or regional availability issue. | Select a supported EKS version/region and verify service quotas. |
| Node groups fail or have no ready nodes | Instance capacity, IAM, subnet IP capacity, or egress issue. | Inspect EKS node-group health; verify node role, private subnet routes, IP capacity, and required AWS API/image-pull egress. |
| `InvalidKeyPair.NotFound` | Key-pair name is misspelled or in another region. | Use the exact regional key name `mukesh` in `us-east-1`. |
| S3 bucket name conflict | Bucket names are globally unique. | Choose a new unused `S3BucketName`. |
| `kubectl` cannot connect | EKS endpoint is private-only. | Run commands from a network connected to the VPC or deliberately enable restricted public endpoint access. |
| Controller reports `AccessDenied` | Pod Identity association or service-account settings do not match the Helm release. | Compare Helm namespace/service account with `AlbControllerNamespace` and `AlbControllerServiceAccountName`; inspect controller logs and association status. |
| Ingress has no ALB address | Controller is not ready, Ingress class is wrong, subnet tags are missing, or AWS API egress is blocked. | Check controller deployment/events, `ingressClassName: alb`, public-subnet discovery tags, and node/pod egress through NAT or endpoints. |
| ALB target health is unhealthy/503 | Backend Service ports, target type, health-check path, or pod reachability is wrong. | Check Service endpoints/ports and Ingress annotations; inspect controller logs and target health. |
| Bastion bootstrap / DB issues | Bootstrap runs via systemd (`spendsmart-cluster-bootstrap.service`); CloudFormation no longer waits on `ClusterBootstrap`. | Ensure `scripts/sync-bastion-assets.sh` ran before deploy. On bastion: `sudo tail -f /var/log/spendsmart-cluster-bootstrap.log` or `sudo bash scripts/bastion-recover-bootstrap.sh`. |
| `kubectl get nodes` → `dial tcp 10.x.x.x:443: i/o timeout` from bastion | EKS API is private-only; bastion→cluster SG rules must exist **before** bootstrap. Older templates added those rules only after the bastion nested stack finished. | Update to current `bastion` template (ingress in nested stack) or manually allow TCP 443 from bastion SG to `EksClusterSecurityGroupId` (and 443/22 to nodes SG). Then retry `kubectl get nodes`. |

## Delete and Cost Cleanup

Remove application Ingress resources first so the controller can delete their ALBs and target groups, then delete the CloudFormation stack:

```sh
aws cloudformation delete-stack \
  --stack-name spendsmart-dev \
  --region us-east-1
aws cloudformation wait stack-delete-complete \
  --stack-name spendsmart-dev \
  --region us-east-1
```

CloudFormation deletes the S3 bucket as part of stack cleanup. If it contains objects or versions, empty it before deleting the stack; otherwise bucket deletion can fail and leave cleanup incomplete.

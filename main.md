| # | Resource / Component | AWS Service | Purpose |
|---:|---|---|---|
| 1 | VPC | Amazon VPC | Main network for SpendSmart |
| 2 | Internet Gateway | Amazon VPC | Internet connectivity for public subnets |
| 3 | Public Subnet 1 | Amazon VPC | Public resources in AZ1 |
| 4 | Public Subnet 2 | Amazon VPC | Public resources in AZ2 |
| 5 | Private Subnet 1 | Amazon VPC | Private workloads in AZ1 |
| 6 | Private Subnet 2 | Amazon VPC | Private workloads in AZ2 |
| 7 | Public Route Table | Amazon VPC | Routes public subnet traffic |
| 8 | Public Internet Route | Amazon VPC | Routes traffic to Internet Gateway |
| 9 | Public Subnet Route Associations | Amazon VPC | Associates public subnets with public route table |
| 10 | NAT Gateway 1 | Amazon VPC | Outbound internet access for private AZ1 |
| 11 | NAT Gateway 2 | Amazon VPC | Outbound internet access for private AZ2 |
| 12 | NAT Gateway Elastic IP 1 | Amazon EC2 | Public IP for NAT Gateway 1 |
| 13 | NAT Gateway Elastic IP 2 | Amazon EC2 | Public IP for NAT Gateway 2 |
| 14 | Private Route Table 1 | Amazon VPC | Routing for private AZ1 |
| 15 | Private Route Table 2 | Amazon VPC | Routing for private AZ2 |
| 16 | Private NAT Route 1 | Amazon VPC | Sends private AZ1 traffic through NAT |
| 17 | Private NAT Route 2 | Amazon VPC | Sends private AZ2 traffic through NAT |
| 18 | Private Subnet Route Associations | Amazon VPC | Associates private subnets with route tables |
| 19 | Bastion Security Group | Amazon EC2/VPC | Controls access to Bastion |
| 20 | Bastion EC2 Instance | Amazon EC2 | Administration/jump server |
| 21 | Bastion Elastic IP | Amazon EC2 | Static public IP for Bastion |
| 22 | Bastion EIP Association | Amazon EC2 | Associates EIP with Bastion |
| 23 | EKS Cluster IAM Role | AWS IAM | Permissions required by EKS |
| 24 | EKS Node IAM Role | AWS IAM | Permissions for worker nodes |
| 25 | EKS Cluster | Amazon EKS | Kubernetes control plane |
| 26 | EKS Nodes Security Group | Amazon EC2/VPC | Controls traffic to worker nodes |
| 27 | EKS Node Launch Template | Amazon EC2 | Defines worker-node EC2 configuration |
| 28 | EKS Managed Node Group AZ1 | Amazon EKS | Worker nodes in Availability Zone 1 |
| 29 | EKS Managed Node Group AZ2 | Amazon EKS | Worker nodes in Availability Zone 2 |
| 30 | EKS Pod Identity Agent | Amazon EKS | Provides pod-to-IAM identity integration |
| 31 | EKS VPC CNI | Amazon EKS | Kubernetes pod networking |
| 32 | EKS kube-proxy | Amazon EKS | Kubernetes service/network routing |
| 33 | EKS CoreDNS | Amazon EKS | Kubernetes DNS |
| 34 | ALB Controller IAM Role | AWS IAM | Permissions for AWS Load Balancer Controller |
| 35 | ALB Controller Pod Identity Association | Amazon EKS | Connects Kubernetes service account to IAM role |
| 36 | S3 Data Bucket | Amazon S3 | Stores SpendSmart data and Athena results |
| 37 | Glue Database | AWS Glue | Stores data catalog metadata |
| 38 | Glue IAM Role | AWS IAM | Permissions for Glue |
| 39 | Glue S3 Policy | AWS IAM | Allows Glue to access S3 |
| 40 | Athena Workgroup | Amazon Athena | Controls SpendSmart Athena queries |
| 41 | Analytics IAM Role | AWS IAM | IAM role for analytics access |
| 42 | Analytics IAM Policy | AWS IAM | Permissions for analytics workloads |
| 43 | CloudFormation Outputs | AWS CloudFormation | Exposes IDs, ARNs, endpoints, bucket names, etc. |
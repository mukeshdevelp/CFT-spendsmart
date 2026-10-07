From the `CFT` directory in account `047078339928`, package the root and nested templates to the dedicated bucket in `us-east-1`, then create the stack. Before deployment, confirm `S3BucketName` is globally unique. `BastionSshCidrs` is a comma-separated list in `parameters.json`; this configuration includes `0.0.0.0/0`, which permits SSH from any IPv4 address. The EC2 key-pair parameter is set to the verified `observabilty.pem` key.

```sh
aws cloudformation package \
  --template-file main.yml \
  --s3-bucket spendsmart-cfn-packages-047078339928-us-east-1 \
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

Inspect status, resources, parameters, events, and outputs:

```sh
aws cloudformation describe-stacks --stack-name spendsmart-dev --region us-east-1 --query 'Stacks[0].StackStatus' --output text
aws cloudformation list-stack-resources --stack-name spendsmart-dev --region us-east-1 --output table
aws cloudformation describe-stacks --stack-name spendsmart-dev --region us-east-1 --query 'Stacks[0].Parameters' --output table
aws cloudformation describe-stack-events --stack-name spendsmart-dev --region us-east-1 --output table
aws cloudformation describe-stacks --stack-name spendsmart-dev --region us-east-1 --query 'Stacks[0].Outputs' --output table
```

For an update, package `main.yml` again and run `aws cloudformation deploy` with the new `packaged.yml`. Enable the optional SpendSmart chart only after provisioning its Kubernetes Secrets, as documented in [ONE_CLICK_DEPLOYMENT.md](ONE_CLICK_DEPLOYMENT.md):

```sh
aws cloudformation package \
  --template-file main.yml \
  --s3-bucket spendsmart-cfn-packages-047078339928-us-east-1 \
  --output-template-file packaged.yml \
  --region us-east-1

aws cloudformation deploy \
  --template-file packaged.yml \
  --stack-name spendsmart-dev \
  --parameter-overrides DeploySpendSmart=true \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

Delete the stack with:

```sh
aws cloudformation delete-stack --stack-name spendsmart-dev --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name spendsmart-dev --region us-east-1
```

The account's current On-Demand Standard vCPU quota is 8. The configured four `c7i-flex.large` nodes plus the `t3.micro` bastion require at least 10 vCPUs, so request a quota increase in this account or lower node counts/disable the bastion before creating the stack.
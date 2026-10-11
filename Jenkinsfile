pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  parameters {
    choice(
      name: 'AWS_REGION',
      choices: ['us-east-1', 'ap-south-1'],
      description: 'Stack region. Use us-east-1 for CUR and this template set.'
    )
    string(
      name: 'CFN_STACK_NAME',
      defaultValue: 'spendsmart-dev',
      description: 'CloudFormation root stack name (main.yml)'
    )
    string(
      name: 'CFN_TEMPLATE_BUCKET',
      defaultValue: 'spendsmart-cfn-packages',
      description: 'S3 bucket for packaged nested templates and bastion-assets'
    )
    string(
      name: 'S3_BUCKET_NAME',
      defaultValue: 'athena-results-spendsmart-dev',
      description: 'Data/CUR S3 bucket parameter'
    )
    string(
      name: 'EXISTING_EC2_KEY_NAME',
      defaultValue: 'mukesh',
      description: 'EC2 key pair name in the deployment region'
    )
    string(
      name: 'BASTION_SSH_CIDRS',
      defaultValue: '0.0.0.0/0',
      description: 'Comma-separated bastion SSH CIDR allowlist'
    )
    booleanParam(
      name: 'WAIT_FOR_STACK',
      defaultValue: true,
      description: 'Wait for stack create/update to finish'
    )
  }

  environment {
    AWS_DEFAULT_REGION = "${params.AWS_REGION}"
    PACKAGED_TEMPLATE = 'packaged.yml'
    DEPLOY_PARAMETERS = 'jenkins-parameters.json'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Preflight') {
      steps {
        script {
          withAwsCredentials {
            sh '''
            set -eu
            command -v aws python3 >/dev/null
            test -f main.yml 
            test -f parameters.json
            test -n "${CFN_TEMPLATE_BUCKET}"
            aws sts get-caller-identity
            aws s3api head-bucket --bucket "${CFN_TEMPLATE_BUCKET}"
          '''
          }
        }
      }
    }

    stage('Prepare deploy parameters') {
      steps {
        sh '''
          set -eu
          python3 <<PY
          import json, os
          from pathlib import Path
          overrides = {
              "ExistingEc2KeyName": os.environ["EXISTING_EC2_KEY_NAME"],
              "BastionSshCidrs": os.environ["BASTION_SSH_CIDRS"],
              "S3BucketName": os.environ["S3_BUCKET_NAME"],
              "CfnTemplateBucket": os.environ["CFN_TEMPLATE_BUCKET"],
          }
          base = json.loads(Path("parameters.json").read_text())
          by_key = {p["ParameterKey"]: p for p in base}
          for key, value in overrides.items():
              by_key[key] = {"ParameterKey": key, "ParameterValue": value}
          Path(os.environ["DEPLOY_PARAMETERS"]).write_text(
              json.dumps(list(by_key.values()), indent=2) + "\\n"
          )
          PY
        '''
      }
    }

    stage('Upload bastion bootstrap assets') {
      steps {
        script {
          withAwsCredentials {
            sh 'bash scripts/sync-bastion-assets.sh "${CFN_TEMPLATE_BUCKET}" "${AWS_REGION}"'
          }
        }
      }
    }

    stage('Package and validate') {
      steps {
        script {
          withAwsCredentials {
            sh '''
            set -eu
            aws cloudformation package \
              --template-file main.yml \
              --s3-bucket "${CFN_TEMPLATE_BUCKET}" \
              --output-template-file "${PACKAGED_TEMPLATE}" \
              --region "${AWS_REGION}"
            aws cloudformation validate-template \
              --template-body file://"${PACKAGED_TEMPLATE}" \
              --region "${AWS_REGION}"
          '''
          }
        }
      }
    }

    stage('Deploy stack') {
      steps {
        script {
          withAwsCredentials {
            sh '''
            set -eu
            if aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
              CHANGE_SET_TYPE=UPDATE
              aws cloudformation update-stack \
                --stack-name "${CFN_STACK_NAME}" \
                --template-body file://"${PACKAGED_TEMPLATE}" \
                --parameters file://"${DEPLOY_PARAMETERS}" \
                --capabilities CAPABILITY_NAMED_IAM \
                --region "${AWS_REGION}" || {
                  msg=$(aws cloudformation describe-stack-events --stack-name "${CFN_STACK_NAME}" \
                    --region "${AWS_REGION}" --max-items 1 \
                    --query 'StackEvents[0].ResourceStatusReason' --output text 2>/dev/null || true)
                  echo "$msg" | grep -q "No updates are to be performed"
                }
            else
              CHANGE_SET_TYPE=CREATE
              aws cloudformation create-stack \
                --stack-name "${CFN_STACK_NAME}" \
                --template-body file://"${PACKAGED_TEMPLATE}" \
                --parameters file://"${DEPLOY_PARAMETERS}" \
                --capabilities CAPABILITY_NAMED_IAM \
                --region "${AWS_REGION}"
            fi
            echo "${CHANGE_SET_TYPE}" > .cfn-change-type
          '''
          }
        }
      }
    }

    stage('Wait for stack') {
      when {
        expression { return params.WAIT_FOR_STACK }
      }
      steps {
        script {
          withAwsCredentials {
            sh '''
            set -eu
            CHANGE_SET_TYPE=$(cat .cfn-change-type)
            if [ "$CHANGE_SET_TYPE" = "CREATE" ]; then
              aws cloudformation wait stack-create-complete --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}"
            else
              aws cloudformation wait stack-update-complete --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" || true
            fi
            aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
              --query 'Stacks[0].StackStatus' --output text
          '''
          }
        }
      }
    }

    stage('Stack outputs') {
      steps {
        script {
          withAwsCredentials {
            sh '''
            aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
              --query 'Stacks[0].Outputs' --output table
          '''
          }
        }
      }
    }
  }

  post {
    failure {
      steps {
        script {
          withAwsCredentials {
            sh '''
              set +e
              aws cloudformation describe-stack-events --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
                --max-items 20 \
                --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[Timestamp,LogicalResourceId,ResourceStatusReason]' \
                --output table
            '''
          }
        }
      }
    }
  }
}

void withAwsCredentials(Closure body) {
  withCredentials([[
    $class: 'AmazonWebServicesCredentialsBinding',
    credentialsId: 'aws-creds',
    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
  ]]) {
    body()
  }
}

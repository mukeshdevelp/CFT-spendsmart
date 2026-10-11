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
      description: 'CloudFormation root stack name'
    )
    string(
      name: 'CFN_TEMPLATE_BUCKET',
      defaultValue: '',
      description: 'S3 bucket for packaged nested templates (must exist in AWS_REGION)'
    )
    string(
      name: 'S3_BUCKET_NAME',
      defaultValue: 'athena-results-spendsmart-dev',
      description: 'S3 bucket for data, CUR, and Athena results (created/deleted with stack)'
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
    choice(
      name: 'SPENDSMART_WORKLOAD_MODE',
      choices: ['LeaveExisting', 'InstallNew'],
      description: 'LeaveExisting = infra only; use Jenkinsfile.helm for chart deploy'
    )
    string(
      name: 'SPENDSMART_VALUES_S3_URI',
      defaultValue: '',
      description: 'Optional Helm values URI. Empty + UPLOAD_CLIENT_VALUES uses s3://<template-bucket>/client-a-values.yaml'
    )
    booleanParam(
      name: 'UPLOAD_CLIENT_VALUES',
      defaultValue: true,
      description: 'Upload client-a-values.yaml from this repo to the template bucket'
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
        sh 'pwd && ls -la'
      }
    }

    stage('Preflight') {
      steps {
        sh '''
          set -euo pipefail
          command -v aws >/dev/null
          aws --version
          test -f main.yml
          test -f parameters.json
          if [ -z "${CFN_TEMPLATE_BUCKET}" ]; then
            echo "CFN_TEMPLATE_BUCKET is required"
            exit 1
          fi
          aws s3api head-bucket --bucket "${CFN_TEMPLATE_BUCKET}"
        '''
      }
    }

    stage('Prepare deploy parameters') {
      steps {
        sh '''
          set -euo pipefail
          VALUES_URI="${SPENDSMART_VALUES_S3_URI}"
          if [ -z "$VALUES_URI" ] && [ "${UPLOAD_CLIENT_VALUES}" = "true" ]; then
            VALUES_URI="s3://${CFN_TEMPLATE_BUCKET}/client-a-values.yaml"
          fi
          export VALUES_URI
          python3 <<PY
          import json
          import os
          from pathlib import Path

          overrides = {
              "ExistingEc2KeyName": os.environ["EXISTING_EC2_KEY_NAME"],
              "BastionSshCidrs": os.environ["BASTION_SSH_CIDRS"],
              "S3BucketName": os.environ["S3_BUCKET_NAME"],
              "SpendSmartWorkloadMode": os.environ["SPENDSMART_WORKLOAD_MODE"],
              "SpendSmartValuesS3Uri": os.environ.get("VALUES_URI", ""),
          }
          base = json.loads(Path("parameters.json").read_text())
          by_key = {p["ParameterKey"]: p for p in base}
          for key, value in overrides.items():
              by_key[key] = {"ParameterKey": key, "ParameterValue": value}
          Path(os.environ["DEPLOY_PARAMETERS"]).write_text(
              json.dumps(list(by_key.values()), indent=2) + "\\n"
          )
          PY
          cat "${DEPLOY_PARAMETERS}"
        '''
      }
    }

    stage('Upload Helm values') {
      when {
        expression { return params.UPLOAD_CLIENT_VALUES }
      }
      steps {
        sh '''
          set -euo pipefail
          test -f client-a-values.yaml
          aws s3 cp client-a-values.yaml "s3://${CFN_TEMPLATE_BUCKET}/client-a-values.yaml"
        '''
      }
    }

    stage('Package templates') {
      steps {
        sh '''
          set -euo pipefail
          aws cloudformation package \
            --template-file main.yml \
            --s3-bucket "${CFN_TEMPLATE_BUCKET}" \
            --output-template-file "${PACKAGED_TEMPLATE}" \
            --region "${AWS_REGION}"
        '''
      }
    }

    stage('Validate packaged template') {
      steps {
        sh '''
          set -euo pipefail
          aws cloudformation validate-template \
            --template-body file://"${PACKAGED_TEMPLATE}" \
            --region "${AWS_REGION}"
        '''
      }
    }

    stage('Deploy stack') {
      steps {
        sh '''
          set -euo pipefail
          if aws cloudformation describe-stacks \
            --stack-name "${CFN_STACK_NAME}" \
            --region "${AWS_REGION}" >/dev/null 2>&1; then
            CHANGE_SET_TYPE=UPDATE
            aws cloudformation update-stack \
              --stack-name "${CFN_STACK_NAME}" \
              --template-body file://"${PACKAGED_TEMPLATE}" \
              --parameters file://"${DEPLOY_PARAMETERS}" \
              --capabilities CAPABILITY_NAMED_IAM \
              --region "${AWS_REGION}"
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

    stage('Wait for stack') {
      when {
        expression { return params.WAIT_FOR_STACK }
      }
      steps {
        sh '''
          set -euo pipefail
          CHANGE_SET_TYPE=$(cat .cfn-change-type)
          if [ "$CHANGE_SET_TYPE" = "CREATE" ]; then
            aws cloudformation wait stack-create-complete \
              --stack-name "${CFN_STACK_NAME}" \
              --region "${AWS_REGION}"
          else
            aws cloudformation wait stack-update-complete \
              --stack-name "${CFN_STACK_NAME}" \
              --region "${AWS_REGION}"
          fi
          aws cloudformation describe-stacks \
            --stack-name "${CFN_STACK_NAME}" \
            --region "${AWS_REGION}" \
            --query 'Stacks[0].StackStatus' \
            --output text
        '''
      }
    }

    stage('Stack outputs') {
      steps {
        sh '''
          set -euo pipefail
          aws cloudformation describe-stacks \
            --stack-name "${CFN_STACK_NAME}" \
            --region "${AWS_REGION}" \
            --query 'Stacks[0].Outputs' \
            --output table
        '''
      }
    }
  }

  post {
    failure {
      sh '''
        set +e
        aws cloudformation describe-stack-events \
          --stack-name "${CFN_STACK_NAME}" \
          --region "${AWS_REGION}" \
          --max-items 20 \
          --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[Timestamp,LogicalResourceId,ResourceStatusReason]' \
          --output table
      '''
    }
  }
}

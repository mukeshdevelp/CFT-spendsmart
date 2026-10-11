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
    booleanParam(
      name: 'DEPLOY_SPENDSMART',
      defaultValue: true,
      description: 'Nested SpendSmart stack (Helm + Keycloak); requires Harbor credentials'
    )
    string(
      name: 'CREDENTIAL_HARBOR',
      defaultValue: 'harbor-creds',
      description: 'Jenkins Username/password — same as docker login harbor.ldc.opstree.dev'
    )
  }

  environment {
    AWS_REGION = "${params.AWS_REGION}"
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
        script {
          def harborCredId = params.CREDENTIAL_HARBOR?.trim() ?: 'harbor-creds'
          withCredentials([usernamePassword(
            credentialsId: harborCredId,
            usernameVariable: 'HARBOR_USERNAME',
            passwordVariable: 'HARBOR_PASSWORD',
          )]) {
            sh '''
            set -eu
            export EXISTING_EC2_KEY_NAME="${EXISTING_EC2_KEY_NAME}"
            export BASTION_SSH_CIDRS="${BASTION_SSH_CIDRS}"
            export S3_BUCKET_NAME="${S3_BUCKET_NAME}"
            export CFN_TEMPLATE_BUCKET="${CFN_TEMPLATE_BUCKET}"
            export DEPLOY_SPENDSMART="${DEPLOY_SPENDSMART}"
            export CFN_PARAMETERS_OUT="${DEPLOY_PARAMETERS}"
            python3 scripts/merge-cfn-parameters.py
            '''
          }
        }
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
      sh 'echo "Error: Stack deployment failed"'
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

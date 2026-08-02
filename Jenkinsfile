// Jenkinsfile
// Jenkins Pipeline for Terraform Infrastructure

pipeline {
    agent any

    // ─────────────────────────────
    // ENVIRONMENT VARIABLES
    // ─────────────────────────────
    environment {
        // AWS Credentials
        AWS_CREDENTIALS     = credentials('aws-credentials')
        AWS_ACCESS_KEY_ID   = "${AWS_CREDENTIALS_USR}"
        AWS_SECRET_ACCESS_KEY = "${AWS_CREDENTIALS_PSW}"
        AWS_DEFAULT_REGION  = "us-east-1"

        // Terraform settings
        TF_VERSION          = "1.6.0"
        TF_WORKING_DIR      = "terraform"
        TF_VAR_FILE         = "environments/${params.ENVIRONMENT}.tfvars"

        // S3 Backend
        TF_STATE_BUCKET     = "murthy-terraform-state"
        TF_STATE_KEY        = "${params.ENVIRONMENT}/terraform.tfstate"
        TF_LOCK_TABLE       = "terraform-state-lock"

        // Notification
        SLACK_CHANNEL       = "#terraform-deployments"
    }

    // ─────────────────────────────
    // PARAMETERS
    // ─────────────────────────────
    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['dev', 'staging', 'production'],
            description: 'Target environment'
        )
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'Terraform action'
        )
        string(
            name: 'TF_VERSION',
            defaultValue: '1.6.0',
            description: 'Terraform version'
        )
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Skip manual approval (dev only!)'
        )
    }

    // ─────────────────────────────
    // OPTIONS
    // ─────────────────────────────
    options {
        // Only ONE deployment at a time!
        disableConcurrentBuilds()

        // Timeout after 2 hours
        timeout(time: 2, unit: 'HOURS')

        // Keep last 10 builds
        buildDiscarder(logRotator(numToKeepStr: '10'))

        // Add timestamps
        timestamps()

        // ANSI color in logs
        // ansiColor('xterm')
    }

    stages {

        // ─────────────────────────────
        // STAGE 1: Checkout
        // ─────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()
                }

                echo """
                =========================================
                Environment : ${params.ENVIRONMENT}
                Action      : ${params.ACTION}
                Branch      : ${env.BRANCH_NAME}
                Commit      : ${env.GIT_COMMIT_SHORT}
                Author      : ${env.GIT_AUTHOR}
                =========================================
                """

                slackSend(
                    channel: env.SLACK_CHANNEL,
                    color: '#FFFF00',
                    message: """
                        🚀 *Terraform Pipeline Started*
                        Environment: ${params.ENVIRONMENT}
                        Action: ${params.ACTION}
                        Branch: ${env.BRANCH_NAME}
                        By: ${env.GIT_AUTHOR}
                    """
                )
            }
        }

        // ─────────────────────────────
        // STAGE 2: Install Terraform
        // ─────────────────────────────
        stage('Install Terraform') {
            steps {
                sh """
                    # Check if terraform installed
                    if ! command -v terraform &> /dev/null; then
                        echo "Installing Terraform ${params.TF_VERSION}..."
                        wget -q \
                            https://releases.hashicorp.com/terraform/${params.TF_VERSION}/terraform_${params.TF_VERSION}_linux_amd64.zip
                        unzip -q terraform_${params.TF_VERSION}_linux_amd64.zip
                        sudo mv terraform /usr/local/bin/
                        rm terraform_${params.TF_VERSION}_linux_amd64.zip
                    fi

                    terraform version
                    echo "Terraform ready! ✅"
                """
            }
        }

        // ─────────────────────────────
        // STAGE 3: Setup S3 Backend
        // ─────────────────────────────
        stage('Setup Remote State') {
            steps {
                sh """
                    echo "Checking S3 backend..."

                    # Create S3 bucket if not exists
                    aws s3api head-bucket \
                        --bucket ${TF_STATE_BUCKET} 2>/dev/null || \
                    aws s3api create-bucket \
                        --bucket ${TF_STATE_BUCKET} \
                        --region ${AWS_DEFAULT_REGION}

                    # Enable versioning
                    aws s3api put-bucket-versioning \
                        --bucket ${TF_STATE_BUCKET} \
                        --versioning-configuration Status=Enabled

                    # Enable encryption
                    aws s3api put-bucket-encryption \
                        --bucket ${TF_STATE_BUCKET} \
                        --server-side-encryption-configuration '{
                            "Rules": [{
                                "ApplyServerSideEncryptionByDefault": {
                                    "SSEAlgorithm": "AES256"
                                }
                            }]
                        }'

                    # Create DynamoDB lock table
                    aws dynamodb describe-table \
                        --table-name ${TF_LOCK_TABLE} 2>/dev/null || \
                    aws dynamodb create-table \
                        --table-name ${TF_LOCK_TABLE} \
                        --attribute-definitions \
                            AttributeName=LockID,AttributeType=S \
                        --key-schema \
                            AttributeName=LockID,KeyType=HASH \
                        --billing-mode PAY_PER_REQUEST

                    echo "Remote state ready! ✅"
                """
            }
        }

        // ─────────────────────────────
        // STAGE 4: Terraform Init
        // ─────────────────────────────
        stage('Terraform Init') {
            steps {
                dir(env.TF_WORKING_DIR) {
                    sh """
                        echo "Initializing Terraform..."

                        terraform init \
                            -backend-config="bucket=${TF_STATE_BUCKET}" \
                            -backend-config="key=${TF_STATE_KEY}" \
                            -backend-config="region=${AWS_DEFAULT_REGION}" \
                            -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
                            -backend-config="encrypt=true" \
                            -reconfigure \
                            -input=false

                        echo "Init complete! ✅"
                    """
                }
            }
        }

        // ─────────────────────────────
        // STAGE 5: Terraform Validate
        // ─────────────────────────────
        stage('Terraform Validate') {
            steps {
                dir(env.TF_WORKING_DIR) {
                    sh """
                        echo "Validating Terraform..."
                        terraform validate
                        echo "Validation passed! ✅"
                    """
                }
            }
        }

        // ─────────────────────────────
        // STAGE 6: Terraform Format
        // ─────────────────────────────
        stage('Terraform Format Check') {
            steps {
                dir(env.TF_WORKING_DIR) {
                    sh """
                        echo "Checking formatting..."
                        terraform fmt -check -recursive || {
                            echo "Format issues found!"
                            terraform fmt -diff -recursive
                            exit 1
                        }
                        echo "Format check passed! ✅"
                    """
                }
            }
        }

        // ─────────────────────────────
        // STAGE 7: Security Scan
        // ─────────────────────────────
        stage('Security Scan') {
            steps {
                sh """
                    # Install tfsec
                    if ! command -v tfsec &> /dev/null; then
                        wget -q -O tfsec \
                            https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-linux-amd64
                        chmod +x tfsec
                        sudo mv tfsec /usr/local/bin/
                    fi

                    # Run security scan
                    tfsec ${TF_WORKING_DIR} \
                        --format json \
                        --out tfsec-report.json \
                        || true

                    # Check for HIGH/CRITICAL issues
                    CRITICAL=\$(cat tfsec-report.json | \
                        python3 -c "
import sys, json
data = json.load(sys.stdin)
critical = [r for r in data.get('results', [])
    if r['severity'] in ['CRITICAL', 'HIGH']]
print(len(critical))
")
                    echo "Critical issues found: \$CRITICAL"

                    if [ "\$CRITICAL" -gt "0" ]; then
                        echo "Critical security issues found!"
                        cat tfsec-report.json
                        # Don't fail - just warn
                    fi
                """

                archiveArtifacts(
                    artifacts: 'tfsec-report.json',
                    allowEmptyArchive: true
                )
            }
        }

        // ─────────────────────────────
        // STAGE 8: Terraform Plan
        // ─────────────────────────────
        stage('Terraform Plan') {
            steps {
                dir(env.TF_WORKING_DIR) {
                    sh """
                        echo "Running Terraform plan..."

                        terraform plan \
                            -var-file=${env.TF_VAR_FILE} \
                            -out=tfplan \
                            -input=false \
                            -detailed-exitcode \
                            2>&1 | tee plan-output.txt

                        EXIT_CODE=\${PIPESTATUS[0]}

                        if [ \$EXIT_CODE -eq 0 ]; then
                            echo "No changes needed! ✅"
                        elif [ \$EXIT_CODE -eq 2 ]; then
                            echo "Changes detected! Plan ready! ✅"
                        else
                            echo "Plan failed! ❌"
                            exit 1
                        fi
                    """

                    // Show plan in human readable format
                    sh """
                        terraform show \
                            -no-color tfplan \
                            > plan-readable.txt
                        cat plan-readable.txt
                    """
                }

                // Archive plan files
                archiveArtifacts(
                    artifacts: """
                        ${TF_WORKING_DIR}/plan-output.txt,
                        ${TF_WORKING_DIR}/plan-readable.txt
                    """,
                    allowEmptyArchive: true
                )

                // Notify plan ready
                slackSend(
                    channel: env.SLACK_CHANNEL,
                    color: '#FFFF00',
                    message: """
                        📋 *Terraform Plan Ready*
                        Environment: ${params.ENVIRONMENT}
                        Action: ${params.ACTION}
                        Approve here: ${env.BUILD_URL}input
                        Plan output: ${env.BUILD_URL}artifact/terraform/plan-readable.txt
                    """
                )
            }
        }

        // ─────────────────────────────
        // STAGE 9: Manager Approval
        // Skip for dev with AUTO_APPROVE
        // ─────────────────────────────
        stage('Manager Approval') {
            when {
                not {
                    allOf {
                        expression { params.ENVIRONMENT == 'dev' }
                        expression { params.AUTO_APPROVE == true }
                    }
                }
            }
            steps {
                script {
                    // Set timeout based on environment
                    def timeoutHours = params.ENVIRONMENT == 'production' ? 4 : 1

                    timeout(time: timeoutHours, unit: 'HOURS') {
                        def approvalMessage = """
                            Review Terraform Plan:
                            ${env.BUILD_URL}artifact/terraform/plan-readable.txt

                            Environment: ${params.ENVIRONMENT}
                            Action: ${params.ACTION}
                            Branch: ${env.BRANCH_NAME}

                            Do you approve this deployment?
                        """

                        // Production needs senior approval
                        if (params.ENVIRONMENT == 'production') {
                            input(
                                message: approvalMessage,
                                ok: 'Approve Production Deploy!',
                                submitter: 'admin,senior-dev,team-lead'
                            )
                        } else {
                            input(
                                message: approvalMessage,
                                ok: 'Approve Deploy!'
                            )
                        }
                    }
                }
                echo "Deployment approved! ✅"
            }
        }

        // ─────────────────────────────
        // STAGE 10: Terraform Apply
        // ─────────────────────────────
        stage('Terraform Apply') {
            when {
                expression {
                    params.ACTION == 'apply' ||
                    params.ACTION == 'destroy'
                }
            }
            steps {
                dir(env.TF_WORKING_DIR) {
                    script {
                        if (params.ACTION == 'apply') {
                            sh """
                                echo "Applying Terraform plan..."
                                terraform apply \
                                    -input=false \
                                    -auto-approve \
                                    tfplan \
                                    2>&1 | tee apply-output.txt

                                echo "Apply complete! ✅"
                            """
                        } else if (params.ACTION == 'destroy') {
                            sh """
                                echo "Destroying infrastructure..."
                                terraform destroy \
                                    -var-file=${env.TF_VAR_FILE} \
                                    -input=false \
                                    -auto-approve \
                                    2>&1 | tee destroy-output.txt

                                echo "Destroy complete! ✅"
                            """
                        }
                    }
                }

                archiveArtifacts(
                    artifacts: """
                        ${TF_WORKING_DIR}/apply-output.txt,
                        ${TF_WORKING_DIR}/destroy-output.txt
                    """,
                    allowEmptyArchive: true
                )
            }
        }

        // ─────────────────────────────
        // STAGE 11: Get Outputs
        // ─────────────────────────────
        stage('Capture Outputs') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                dir(env.TF_WORKING_DIR) {
                    sh """
                        echo "Capturing Terraform outputs..."

                        terraform output \
                            -json > tf-outputs.json

                        echo "Outputs:"
                        cat tf-outputs.json

                        # Save specific outputs
                        RDS_ENDPOINT=\$(terraform output \
                            -raw rds_primary_endpoint 2>/dev/null || echo "N/A")
                        REDIS_ENDPOINT=\$(terraform output \
                            -raw redis_primary_endpoint 2>/dev/null || echo "N/A")
                        APP_URL=\$(terraform output \
                            -raw app_load_balancer_dns 2>/dev/null || echo "N/A")

                        echo "RDS: \$RDS_ENDPOINT"
                        echo "Redis: \$REDIS_ENDPOINT"
                        echo "App: \$APP_URL"
                    """

                    archiveArtifacts(
                        artifacts: 'tf-outputs.json',
                        allowEmptyArchive: true
                    )
                }
            }
        }
    }

    // ─────────────────────────────
    // POST ACTIONS
    // ─────────────────────────────
    post {
        always {
            echo "Pipeline finished!"
            cleanWs()
        }

        success {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'good',
                message: """
                    ✅ *Terraform ${params.ACTION} SUCCESS*
                    Environment: ${params.ENVIRONMENT}
                    Branch: ${env.BRANCH_NAME}
                    Build: #${env.BUILD_NUMBER}
                    Duration: ${currentBuild.durationString}
                    Logs: ${env.BUILD_URL}
                """
            )
        }

        failure {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'danger',
                message: """
                    ❌ *Terraform ${params.ACTION} FAILED*
                    Environment: ${params.ENVIRONMENT}
                    Branch: ${env.BRANCH_NAME}
                    Build: #${env.BUILD_NUMBER}
                    Logs: ${env.BUILD_URL}
                    @here Please check immediately!
                """
            )
        }

        aborted {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'warning',
                message: """
                    ⚠️ *Terraform ${params.ACTION} ABORTED*
                    Environment: ${params.ENVIRONMENT}
                    Build: #${env.BUILD_NUMBER}
                    (Approval timeout or manual abort)
                """
            )
        }
    }
}

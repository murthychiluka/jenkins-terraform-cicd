pipeline {
    agent any

    environment {
        TF_WORKING_DIR    = "terraform"
        AWS_DEFAULT_REGION = "us-east-1"
    }

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
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Skip approval for dev'
        )
    }

    options {
        disableConcurrentBuilds()
        timeout(time: 2, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
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
                Commit      : ${env.GIT_COMMIT_SHORT}
                Author      : ${env.GIT_AUTHOR}
                =========================================
                """
            }
        }

        // ─────────────────────────────
        // STAGE 2: Install Terraform
        // ─────────────────────────────
        stage('Install Terraform') {
            steps {
                sh '''
                    if command -v terraform &> /dev/null; then
                        echo "Terraform already installed!"
                        terraform version
                    else
                        echo "Installing Terraform..."
                        wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
                        unzip -q terraform_1.6.0_linux_amd64.zip
                        sudo mv terraform /usr/local/bin/
                        rm -f terraform_1.6.0_linux_amd64.zip
                        terraform version
                        echo "Terraform installed! ✅"
                    fi
                '''
            }
        }

        // ─────────────────────────────
        // STAGE 3: Terraform Init
        // ─────────────────────────────
        stage('Terraform Init') {
            steps {
                withCredentials([[
                    $class: 'UsernamePasswordMultiBinding',
                    credentialsId: 'aws-credentials',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        echo "Initializing Terraform..."
                     
                        terraform init
                        echo "Init complete! ✅"
                    '''
                }
            }
        }

        // ─────────────────────────────
        // STAGE 4: Terraform Validate
        // ─────────────────────────────
        stage('Terraform Validate') {
            steps {
                sh '''
                    echo "Validating..."
            
                    terraform validate
                    echo "Validation passed! ✅"
                '''
            }
        }

        // ─────────────────────────────
        // STAGE 5: Terraform Plan
        // ─────────────────────────────
        stage('Terraform Plan') {
            steps {
                withCredentials([[
                    $class: 'UsernamePasswordMultiBinding',
                    credentialsId: 'aws-credentials',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh """
                        echo "Running plan for ${params.ENVIRONMENT}..."
    
                        terraform plan \
                            -var='environment=${params.ENVIRONMENT}' \
                            -out=tfplan
                        echo "Plan complete! ✅"
                    """
                }
            }
        }

        // ─────────────────────────────
        // STAGE 6: Approval
        // ─────────────────────────────
        stage('Approval') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' || params.ACTION == 'destroy' }
                    expression { params.AUTO_APPROVE == false }
                }
            }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input(
                        message: "Deploy to ${params.ENVIRONMENT}?",
                        ok: 'Yes, Proceed!'
                    )
                }
                echo "Approved! ✅"
            }
        }

        // ─────────────────────────────
        // STAGE 7: Terraform Apply
        // ─────────────────────────────
        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                withCredentials([[
                    $class: 'UsernamePasswordMultiBinding',
                    credentialsId: 'aws-credentials',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        echo "Applying..."
                        
                        terraform apply \
                            -auto-approve \
                            tfplan
                        echo "Apply complete! ✅"
                    '''
                }
            }
        }

        // ─────────────────────────────
        // STAGE 8: Terraform Destroy
        // ─────────────────────────────
        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([[
                    $class: 'UsernamePasswordMultiBinding',
                    credentialsId: 'aws-credentials',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh """
                        echo "Destroying ${params.ENVIRONMENT}..."
                      
                        terraform destroy \
                            -var='environment=${params.ENVIRONMENT}' \
                            -auto-approve
                        echo "Destroy complete! ✅"
                    """
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline finished!"
            echo "Status: ${currentBuild.result}"
            cleanWs()
        }
        success {
            echo "✅ Pipeline SUCCESS!"
        }
        failure {
            echo "❌ Pipeline FAILED!"
           
        }
        aborted {
            echo "⚠️ Pipeline ABORTED!"
        }
    }
}

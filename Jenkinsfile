properties([
    parameters([
        string(
            defaultValue: 'dev',
            name: 'Environment'
        ),
        choice(
            choices: ['plan', 'apply', 'destroy'], 
            name: 'Terraform_Action'
        )])
])
pipeline {
    agent any
    stages {
        stage('Prepare') {
            steps {
                sh 'echo Preparing'
            }
        }
        stage('Git Clone') {
            steps {
                git branch: 'master', url: 'https://github.com/CodeByMurali/EKS-Terraform-GitHub-Actions.git'
            }
        }
        stage('Terraform init') {
            steps {
                withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                sh 'terraform -chdir=eks/ init'
                }
            }
        }
        stage('Terraform validate') {
            steps {
                withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                sh 'terraform -chdir=eks/ validate'
                }
            }
        }
        stage('Terraform action') {
            steps {
                withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                    script {    
                        if (params.Terraform_Action == 'plan') {
                            sh "terraform -chdir=eks/ plan -var-file=${params.Environment}.tfvars"
                        }   else if (params.Terraform_Action == 'apply') {
                            sh "terraform -chdir=eks/ apply -var-file=${params.Environment}.tfvars -auto-approve"
                        }   else if (params.Terraform_Action == 'destroy') {
                            sh "terraform -chdir=eks/ destroy -var-file=${params.Environment}.tfvars -auto-approve"
                        } else {
                            error "Invalid value for Terraform_Action: ${params.Terraform_Action}"
                        }
                    }
                }
            }
        }
    }
}

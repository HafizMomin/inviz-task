pipeline {
    agent any
    
    environment {
        KUBECONFIG = credentials('KUBECONFIG_FILE')
        HELM_RELEASE_NAME = 'inviz-app'
        HELM_REPO_URL =
    }
    
    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/HafizMomin/inviz-task.git'
            }
        }
        
       
        stage('Deploy Helm Chart') {
            steps {
                script {
                    // Ensure kubectl and helm are installed
                    sh 'kubectl version'
                    sh 'helm version --client'
                    
                    // Set the Kubernetes context to use
                    sh "aws eks --region ap-southeast-1 update-kubeconfig --name eks-cluster-inviz"
                    
                    // Deploy Helm chart
                    sh "helm upgrade --install "
                }
            }
        }
    }
    
    post {
        success {
            echo 'Deployment successful'
        }
        failure {
            echo 'Deployment failed'
        }
    }
}

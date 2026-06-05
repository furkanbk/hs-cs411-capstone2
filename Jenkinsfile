// =============================================================================
// hs-cs411-capstone2 - simple Jenkins pipeline
// -----------------------------------------------------------------------------
// Stages: Unit Test -> Deploy to target (systemd) -> Build & Push Docker
//         -> Deploy to docker -> Deploy to kubernetes
//
// Jenkins setup (only the basics):
//   * Credentials (Manage Jenkins > Credentials > Global):
//       - LAB_SSH_KEY : "SSH Username with private key", username = laborant.
//                       The public half is already on target/docker hosts.
//       - KUBECONFIG  : "Secret file", a kubeconfig that points at
//                       https://kubernetes:6443 (needed only for the k8s stage).
//   * Plugins: Pipeline + Credentials Binding (bundled) + SSH Credentials.
//   * The Jenkins node must have node, npm, docker and kubectl on PATH.
// =============================================================================

pipeline {
    agent any

    environment {
        APP_NAME = 'myapp'
        IMAGE    = "ttl.sh/myapp-${BUILD_NUMBER}:1h"
    }

    stages {

        stage('Unit Test') {
            steps {
                sh 'npm install'
                sh 'node --test'
            }
        }

        stage('Deploy to target') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'LAB_SSH_KEY', keyFileVariable: 'KEY')]) {
                    sh '''
                        set -e
                        tar czf app.tgz index.js package.json node_modules
                        scp -o StrictHostKeyChecking=no -i "$KEY" app.tgz myapp.service laborant@target:/tmp/
                        ssh -o StrictHostKeyChecking=no -i "$KEY" laborant@target "
                            set -e
                            mkdir -p ~/app
                            tar xzf /tmp/app.tgz -C ~/app
                            sudo mv /tmp/myapp.service /etc/systemd/system/myapp.service
                            sudo systemctl daemon-reload
                            sudo systemctl enable myapp
                            sudo systemctl restart myapp
                            sleep 2
                            curl -fsS http://localhost:4444/
                        "
                    '''
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                sh '''
                    set -e
                    docker build -t "$IMAGE" .
                    docker push "$IMAGE"
                '''
            }
        }

        stage('Deploy to docker') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'LAB_SSH_KEY', keyFileVariable: 'KEY')]) {
                    sh '''
                        set -e
                        ssh -o StrictHostKeyChecking=no -i "$KEY" laborant@docker "
                            docker rm -f myapp 2>/dev/null || true
                            docker run -d --name myapp -p 4444:4444 $IMAGE
                            sleep 3
                            curl -fsS http://localhost:4444/
                        "
                    '''
                }
            }
        }

        stage('Deploy to kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        sed "s|IMAGE_PLACEHOLDER|$IMAGE|g" k8s/deployment.yaml | kubectl apply -f -
                        kubectl apply -f k8s/service.yaml
                        kubectl rollout status deployment/myapp --timeout=120s
                        kubectl get pods,svc -l app=myapp
                    '''
                }
            }
        }
    }
}

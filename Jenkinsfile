// =============================================================================
// hs-cs411-capstone2 - full Jenkins pipeline
// -----------------------------------------------------------------------------
// Stages:
//   1. Unit Test          -> npm test
//   2. Package Binary     -> tar.gz with index.js + package.json + node_modules
//   3. Deploy to Target   -> SCP + ssh into laborant@${TARGET_HOST}, run binary
//   4. Build Docker Image -> docker build (single-stage Dockerfile)
//   5. Push to ttl.sh     -> ephemeral registry, 1h TTL
//   6. Deploy to Docker   -> ssh into laborant@${DOCKER_HOST}, pull & run
//   7. Health Check       -> curl the app on the docker host
//   8. Deploy to K8s      -> (STRETCH) apply k8s/ to https://kubernetes:6443
//
// Required Jenkins setup (Manage Jenkins):
//   * Credentials:
//       - LAB_SSH_KEY   (Kind: SSH Username with private key, ID: LAB_SSH_KEY)
//                       The public part is already installed on target/docker
//                       hosts and the user is "laborant".
//       - KUBECONFIG    (Kind: Secret file, ID: KUBECONFIG) - kubeconfig that
//                       points at https://kubernetes:6443. Required only for
//                       the Kubernetes stretch stage.
//   * Tools:
//       - NodeJS-24     (Manage Jenkins > Tools > NodeJS Installations > 24.x)
//   * Plugins:
//       - NodeJS, SSH Agent / Credentials, Pipeline, Workspace Cleanup
// =============================================================================

pipeline {
    agent any

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        ansiColor('xterm')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        APP_NAME     = 'hs-cs411-capstone2'
        APP_PORT     = '4444'

        // Lab machine hostnames (override in the job if your DNS differs).
        TARGET_HOST  = 'target'
        DOCKER_HOST  = 'docker'
        K8S_ENDPOINT = 'https://kubernetes:6443'
        K8S_NAMESPACE = 'default'

        // ttl.sh tag includes build number + short sha for traceability.
        SHORT_SHA   = "${env.GIT_COMMIT?.take(7) ?: 'local'}"
        IMAGE_TAG   = "${env.BUILD_NUMBER}-${SHORT_SHA}"
        TTL_IMAGE   = "ttl.sh/${APP_NAME}:${IMAGE_TAG}-1h"
    }

    tools {
        // Falls back to whatever Node is on PATH if NodeJS-24 isn't installed.
        nodejs 'NodeJS-24'
    }

    stages {

        // -------- 1. Unit test -------------------------------------------------
        stage('Unit Test') {
            steps {
                sh '''
                    set -e
                    echo "Node:  $(node -v)"
                    echo "npm:   $(npm -v)"
                    # node:test runner is built-in to Node >= 18; we still let
                    # npm refresh the lockfile in CI for reproducibility.
                    [ -f package-lock.json ] && npm ci --no-audit --no-fund || npm install --no-audit --no-fund
                    npm test
                '''
            }
            post {
                always {
                    junit testResults: '**/test-results*.xml', allowEmptyResults: true
                }
            }
        }

        // -------- 2. Package binary -------------------------------------------
        stage('Package Binary') {
            steps {
                sh '''
                    set -e
                    mkdir -p dist
                    # "Binary" in the Node world = the JS bundle + dependencies.
                    tar --exclude='./dist' --exclude='./.git' \
                        -czf dist/app.tar.gz index.js package.json node_modules
                    ls -lh dist/app.tar.gz
                '''
                archiveArtifacts artifacts: 'dist/app.tar.gz', fingerprint: true, onlyIfSuccessful: true
            }
        }

        // -------- 3. Deploy to target host ------------------------------------
        stage('Deploy to Target') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'LAB_SSH_KEY',
                                                   keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        set -e
                        echo "==> Copying tarball to laborant@${TARGET_HOST}"
                        scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
                            dist/app.tar.gz "laborant@${TARGET_HOST}:~/app.tar.gz"

                        echo "==> Stopping any previous instance"
                        ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
                            "laborant@${TARGET_HOST}" \
                            "pkill -f 'node index.js' 2>/dev/null || true; sleep 1"

                        echo "==> Extracting and starting app on target"
                        ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
                            "laborant@${TARGET_HOST}" "
                                set -e
                                rm -rf ~/app
                                mkdir -p ~/app
                                tar -xzf ~/app.tar.gz -C ~/app
                                cd ~/app
                                node --version
                                nohup node index.js > ~/app.log 2>&1 &
                                echo \$! > ~/app.pid
                                disown
                                sleep 2
                                echo \"App PID: \$(cat ~/app.pid)\"
                            "

                        echo "==> Health check (target)"
                        ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
                            "laborant@${TARGET_HOST}" \
                            "curl -fsS 'http://127.0.0.1:${APP_PORT}/' || (cat ~/app.log; exit 1)"
                    '''
                }
            }
        }

        // -------- 4. Build Docker image ---------------------------------------
        stage('Build Docker Image') {
            steps {
                sh '''
                    set -e
                    docker --version
                    docker build -t "${APP_NAME}:${IMAGE_TAG}" -f Dockerfile .
                    docker images | grep "${APP_NAME}"
                '''
            }
        }

        // -------- 5. Push to ttl.sh -------------------------------------------
        stage('Push to ttl.sh') {
            steps {
                sh '''
                    set -e
                    docker tag "${APP_NAME}:${IMAGE_TAG}" "${TTL_IMAGE}"
                    # ttl.sh is anonymous, no login required.
                    docker push "${TTL_IMAGE}"
                    echo "Pushed: ${TTL_IMAGE}"
                '''
            }
        }

        // -------- 6. Deploy to docker host ------------------------------------
        stage('Deploy to Docker Host') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'LAB_SSH_KEY',
                                                   keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        set -e
                        echo "==> Pulling ${TTL_IMAGE} on docker host"
                        ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
                            "laborant@${DOCKER_HOST}" "
                                set -e
                                docker --version
                                docker pull ${TTL_IMAGE}

                                # Stop & remove any previous container with the same name.
                                docker stop ${APP_NAME} 2>/dev/null || true
                                docker rm   ${APP_NAME} 2>/dev/null || true

                                docker run -d \
                                    --name ${APP_NAME} \
                                    --restart unless-stopped \
                                    -p ${APP_PORT}:${APP_PORT} \
                                    ${TTL_IMAGE}
                                sleep 3
                                docker ps | grep ${APP_NAME}
                            "
                    '''
                }
            }
        }

        // -------- 7. Health check on docker host ------------------------------
        stage('Health Check') {
            steps {
                sh '''
                    set -e
                    echo "==> Hitting http://${DOCKER_HOST}:${APP_PORT}/"
                    # Retry a few times - the container may need a second to bind.
                    for i in 1 2 3 4 5; do
                        if curl -fsS "http://${DOCKER_HOST}:${APP_PORT}/"; then
                            echo
                            echo "Health check OK"
                            exit 0
                        fi
                        echo "Retry $i..."
                        sleep 2
                    done
                    echo "Health check failed"
                    exit 1
                '''
            }
        }

        // -------- 8. STRETCH: Kubernetes deploy -------------------------------
        stage('Deploy to Kubernetes') {
            when {
                // Skip automatically if the user hasn't created the credential.
                expression { return env.SKIP_K8S != 'true' }
            }
            steps {
                withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
                    sh '''
                        set -e
                        echo "==> kubectl version (server ${K8S_ENDPOINT})"
                        KUBECONFIG="${KUBECONFIG}" kubectl version --short || true

                        echo "==> Substituting image tag in manifests"
                        mkdir -p .k8s-rendered
                        sed "s|REPLACE_IMAGE|${TTL_IMAGE}|g; s|REPLACE_TAG|${IMAGE_TAG}|g" \
                            k8s/deployment.yaml > .k8s-rendered/deployment.yaml
                        cp k8s/service.yaml .k8s-rendered/

                        echo "==> Applying manifests to namespace '${K8S_NAMESPACE}'"
                        KUBECONFIG="${KUBECONFIG}" kubectl --namespace "${K8S_NAMESPACE}" \
                            apply -f .k8s-rendered/

                        echo "==> Waiting for rollout"
                        KUBECONFIG="${KUBECONFIG}" kubectl --namespace "${K8S_NAMESPACE}" \
                            rollout status deployment/${APP_NAME} --timeout=120s

                        echo "==> Verifying"
                        KUBECONFIG="${KUBECONFIG}" kubectl --namespace "${K8S_NAMESPACE}" \
                            get deploy,po,svc -l app=${APP_NAME} -o wide
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Pipeline SUCCESS - image pushed: ${env.TTL_IMAGE}"
        }
        failure {
            echo "Pipeline FAILED - check the failing stage logs above."
        }
    }
}

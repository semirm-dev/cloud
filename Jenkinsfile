pipeline {
    agent {
        node {
            label "ubuntu"
        }
    }

    options {
        disableConcurrentBuilds()
        timeout(time: 10, unit: 'MINUTES')
    }

    environment {
        SLACK_CHANNEL = "#exchange-events"
        SERVICE_NAME = "naga/exchange/services"
        ECR_REPO_URL = "${ECR_BASE_URL}/${SERVICE_NAME}"
        MSG_PREFIX = "*[${SERVICE_NAME}][${BRANCH_NAME}][${BUILD_NUMBER}]*"
        COMMIT = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
        SHORT_COMMIT = "${COMMIT}".take(8)
    }

    stages {
        stage('Start') {
            steps {
            slackSend message: "${MSG_PREFIX}: Pipeline starting... ",
                color: "good",
                channel: "${SLACK_CHANNEL}",
                teamDomain: "${env.SLACK_TEAM_DOMAIN}",
                tokenCredentialId: "${env.SLACK_CREDENTIALS}"
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build image') {
            steps {
                ansiColor('xterm') {
                    retry(2) {
                        sh 'docker build -t ${ECR_REPO_URL}:${BRANCH_NAME}-${BUILD_NUMBER} -t ${ECR_REPO_URL}:${BRANCH_NAME}-latest .'
                    }
                }
            }
        }

        stage('Vulnerability scan') {
            steps {
                aquaMicroscanner imageName: "${ECR_REPO_URL}:${BRANCH_NAME}-${BUILD_NUMBER}", notCompliesCmd: 'exit 1', onDisallowed: 'ignore', outputFormat: 'html'
            }
        }

        stage('Docker push') {
            steps {
                sh 'rm  ~/.dockercfg || true'
                sh 'rm ~/.docker/config.json || true'

                withDockerRegistry([credentialsId:"${ECR_CREDENTIALS}", url:"https://${ECR_BASE_URL}"]) {
                    retry(2) {
                        sh 'docker push ${ECR_REPO_URL}:${BRANCH_NAME}-${BUILD_NUMBER}'
                        sh 'docker push ${ECR_REPO_URL}:${BRANCH_NAME}-latest'
                    }
                }
            }
        }
    }
    post {
        always {
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            slackSend message: "${MSG_PREFIX}: Pipeline finished. | ${env.BUILD_URL}",
                color: "good",
                channel: "${SLACK_CHANNEL}",
                teamDomain: "${env.SLACK_TEAM_DOMAIN}",
                tokenCredentialId: "${env.SLACK_CREDENTIALS}"

            slackSend message: "${MSG_PREFIX}: Exchange services subbmitted for k8 deploy. | ${env.BUILD_URL}",
                color: "good",
                channel: "${SLACK_CHANNEL}",
                teamDomain: "${env.SLACK_TEAM_DOMAIN}",
                tokenCredentialId: "${env.SLACK_CREDENTIALS}"

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-stream-worker'),
                         string(name: 'CONTAINER', value: 'exchange-stream-worker')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-stream-publisher'),
                         string(name: 'CONTAINER', value: 'exchange-stream-publisher')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-stream-cache'),
                         string(name: 'CONTAINER', value: 'exchange-stream-cache')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-orderbook-service'),
                         string(name: 'CONTAINER', value: 'exchange-orderbook-service')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-usersync-service'),
                         string(name: 'CONTAINER', value: 'exchange-usersync-service')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-socket-publisher-worker'),
                         string(name: 'CONTAINER', value: 'exchange-socket-publisher-worker')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-event-logger-worker'),
                         string(name: 'CONTAINER', value: 'exchange-event-logger-worker')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-market-streamer-worker'),
                         string(name: 'CONTAINER', value: 'exchange-market-streamer-worker')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'exchange-error-handler-worker'),
                         string(name: 'CONTAINER', value: 'exchange-error-handler-worker')]
                         
            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'main-api'),
                         string(name: 'CONTAINER', value: 'main-api')]

            build job: 'Naga/Development/service_deploy_k8s_exchange',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'auth-api'),
                         string(name: 'CONTAINER', value: 'auth-api')]
                         
            build job: 'Naga/exchange_production/exchange_postman_api_tests/', 
            parameters: [string(name: 'TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}")], wait: false

        }
        failure {
            slackSend message: "${MSG_PREFIX}: Pipeline failed. | ${env.BUILD_URL}",
                color: "danger",
                channel: "${SLACK_CHANNEL}",
                teamDomain: "${env.SLACK_TEAM_DOMAIN}",
                tokenCredentialId: "${env.SLACK_CREDENTIALS}"
        }
    }
}
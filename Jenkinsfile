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
        SLACK_CHANNEL = "#my-events"
        SERVICE_NAME = "woohoo/my/services"
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

            slackSend message: "${MSG_PREFIX}: my services subbmitted for k8 deploy. | ${env.BUILD_URL}",
                color: "good",
                channel: "${SLACK_CHANNEL}",
                teamDomain: "${env.SLACK_TEAM_DOMAIN}",
                tokenCredentialId: "${env.SLACK_CREDENTIALS}"

            build job: 'woohoo/Development/service_deploy_k8s_my',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'my-svc-worker'),
                         string(name: 'CONTAINER', value: 'my-svc-worker')]

            build job: 'woohoo/Development/service_deploy_k8s_my',
            parameters: [string(name: 'IMAGE_URL', value: "${ECR_REPO_URL}"),
                         string(name: 'IMAGE_TAG', value: "${BRANCH_NAME}-${BUILD_NUMBER}"), 
                         string(name: 'DEPLOYMENT', value: 'my-svc-publisher'),
                         string(name: 'CONTAINER', value: 'my-svc-publisher')]
                         
            build job: 'woohoo/my_production/my_postman_api_tests/', 
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
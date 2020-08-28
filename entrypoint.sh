#!/usr/bin/env bash
set -eo pipefail

/usr/bin/docker --version
exit 0;

# Authenticate to ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output 'text')
ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
if ! aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_REPOSITORY}"; then
  echo "ERROR: Failed to authenticate to ECR for AWS account: ${AWS_ACCOUNT_ID}"
  exit 1
fi

# Build and deploy using docker-compose
echo "Building docker image..."
TAG="${GITHUB_REF}" IMAGE="${DOCKER_IMAGE}" ECR_REPOSITORY="${ECR_REPOSITORY}" docker-compose -f "${DOCKER_COMPOSE_YML}" build
TAG="${GITHUB_REF}" IMAGE="${DOCKER_IMAGE}" ECR_REPOSITORY="${ECR_REPOSITORY}" docker-compose -f "${DOCKER_COMPOSE_YML}" push


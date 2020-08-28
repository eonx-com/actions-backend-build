#!/usr/bin/env bash
set -eox pipefail

# Authenticate to ECR
echo "Authenticating to ECR..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output 'text')
ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
if ! aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_REPOSITORY}"; then
  echo "ERROR: Failed to authenticate to ECR for AWS account: ${AWS_ACCOUNT_ID}"
  exit 1
fi

# Build and deploy using docker-compose
echo "Building docker image..."
TAG="${GITHUB_SHA}" IMAGE="${DOCKER_IMAGE}" ECR_REPOSITORY="${ECR_REPOSITORY}" docker-compose -f "${GITHUB_WORKSPACE}/${DOCKER_COMPOSE_YML}" build
TAG="${GITHUB_SHA}" IMAGE="${DOCKER_IMAGE}" ECR_REPOSITORY="${ECR_REPOSITORY}" docker-compose -f "${GITHUB_WORKSPACE}/${DOCKER_COMPOSE_YML}" push

# Specify the ECS task name for which the task definition will be updated
ecs_task_definition_template_parameter_prefix="/Terraform/ECS/Template/"
ecs_task_definition_template_tag="DEPLOYMENT_IMAGE_TAG"

# Retrieve the task definition template
container_definition_template=$(aws ssm get-parameter \
  --name "${ecs_task_definition_template_parameter_prefix}${ECS_TASK_NAME}" \
  --output text \
  --query Parameter.Value \
)

# Set the image tag in the task definition
container_definition="${container_definition_template/${ecs_task_definition_template_tag}/${GITHUB_SHA}}"

# Remove all null values from the JSON
container_definition=$(json="${container_definition}" jq -n -r 'env.json' | jq 'walk( if type == "object" then with_entries(select(.value != null)) else . end)')

# Extract volumes for use in update command and remove from the JSON as it will generate an error
volumes=$(json="${container_definition}" jq -n -r 'env.json' | jq -r '.volumes')
# If there are no volumes, turn it into an empty array
if [[ "${volumes}" == "null" ]]; then
  volumes="[]"
fi
container_definition=$(json="${container_definition}" jq -n -r 'env.json' | jq -r 'del(.volumes)')

# Extract CPU/memory for use in update command
cpu=$(json="${container_definition}" jq -n -r 'env.json' | jq -r '.cpu')
memory=$(json="${container_definition}" jq -n -r 'env.json' | jq -r '.memory')

# Update the container definition
container_definition_updated=$(aws ecs register-task-definition \
  --family ${ECS_TASK_NAME} \
  --container-definitions "[${container_definition}]" \
  --volumes "${volumes}" \
  --cpu "${cpu}" \
  --memory "${memory}" \
  --network-mode "awsvpc" \
  --execution-role-arn "${ECS_TASK_NAME}EcsExecutionRole" \
  --task-role-arn "${ECS_TASK_NAME}EcsTaskRole" \
  --requires-compatibilities "FARGATE" \
)

# Retrieve the new task definitions ARN
task_definition_arn=$(JSON="${container_definition_updated}" jq -n -r 'env.JSON' | jq -r '.taskDefinition.taskDefinitionArn')

echo "Updating ECS task...";
echo
echo "ECS Cluster:              ${ECS_CLUSTER_NAME}";
echo "ECS Task Name:            ${ECS_TASK_NAME}";
echo "Task Definition ARN:      ${task_definition_arn}";
echo
aws ecs update-service \
  --cluster "${ECS_CLUSTER_NAME}" \
  --service "${ECS_TASK_NAME}" \
  --task-definition "${task_definition_arn}" \
  --force-new-deployment

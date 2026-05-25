#!/bin/bash
set -e

# Script to deploy the Load Balancer CloudFormation Stack
# Usage: ./deploy.sh [KeyName] [Region]

STACK_NAME="LoadBalancerProject"
TEMPLATE_FILE="cloudformation/loadbalancer-template.yaml"
PARAMETERS_FILE="cloudformation/parameters.json"
REGION="${2:-us-east-1}"
KEY_NAME="${1:-default}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Load Balancer CloudFormation Deployment ===${NC}"
echo "Stack Name: $STACK_NAME"
echo "Template: $TEMPLATE_FILE"
echo "Parameters: $PARAMETERS_FILE"
echo "Region: $REGION"
echo "Key Name: $KEY_NAME"

# Validate template
echo -e "\n${YELLOW}Validating CloudFormation template...${NC}"
aws cloudformation validate-template \
  --template-body file://$TEMPLATE_FILE \
  --region $REGION > /dev/null

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Template validation successful${NC}"
else
  echo -e "${RED}✗ Template validation failed${NC}"
  exit 1
fi

# Check if stack already exists
echo -e "\n${YELLOW}Checking if stack already exists...${NC}"
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null; then
  echo -e "${YELLOW}Stack already exists. Updating...${NC}"
  aws cloudformation update-stack \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --parameters file://$PARAMETERS_FILE \
    --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    --region $REGION \
    --capabilities CAPABILITY_NAMED_IAM

  OPERATION="update"
else
  echo -e "${YELLOW}Creating new stack...${NC}"
  aws cloudformation create-stack \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --parameters file://$PARAMETERS_FILE \
    --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    --region $REGION \
    --capabilities CAPABILITY_NAMED_IAM

  OPERATION="create"
fi

# Wait for stack operation to complete
echo -e "\n${YELLOW}Waiting for stack $OPERATION to complete...${NC}"
aws cloudformation wait stack-${OPERATION}-complete \
  --stack-name $STACK_NAME \
  --region $REGION

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Stack $OPERATION successful${NC}"
else
  echo -e "${RED}✗ Stack $OPERATION failed${NC}"
  echo -e "\n${YELLOW}Stack Events:${NC}"
  aws cloudformation describe-stack-events \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`]'
  exit 1
fi

# Display outputs
echo -e "\n${GREEN}=== Stack Outputs ===${NC}"
aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs' \
  --output table

# Save outputs to file
echo -e "\n${YELLOW}Saving outputs to stack-outputs.json...${NC}"
aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs' > stack-outputs.json

echo -e "\n${GREEN}✓ Deployment complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Wait 2-3 minutes for instances to fully initialize"
echo "2. Get the NGINX public IP from stack outputs"
echo "3. Test the load balancer: curl http://<NGINX_IP>/"
echo "4. Run tests: ./scripts/test-loadbalancer.sh"

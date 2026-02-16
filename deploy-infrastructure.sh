#!/bin/bash

# EKS Deployment Script
# This script deploys the complete EKS infrastructure using CloudFormation

set -e

# Configuration
ENVIRONMENT_NAME="eks-prod"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    log_info "AWS CLI found: $(aws --version)"
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl is not installed. You'll need it to manage the cluster."
    else
        log_info "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi
}

wait_for_stack() {
    local stack_name=$1
    log_info "Waiting for stack $stack_name to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" || \
    aws cloudformation wait stack-update-complete \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
}

deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters=$3
    
    log_info "Deploying stack: $stack_name"
    
    if aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" &> /dev/null; then
        log_info "Stack exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" || log_warn "No updates to be performed"
    else
        log_info "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
    fi
    
    wait_for_stack "$stack_name"
    log_info "Stack $stack_name deployed successfully!"
}

# Main deployment
main() {
    log_info "Starting EKS deployment..."
    log_info "Environment: $ENVIRONMENT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Profile: $AWS_PROFILE"
    
    check_aws_cli
    check_kubectl
    
    # Deploy VPC
    log_info "Step 1/3: Deploying VPC infrastructure..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-vpc" \
        "cloudformation/01-vpc.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=${ENVIRONMENT_NAME}"
    
    # Deploy EKS Cluster
    log_info "Step 2/3: Deploying EKS cluster..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-eks-cluster" \
        "cloudformation/02-eks-cluster.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=${ENVIRONMENT_NAME}"
    
    # Deploy Node Groups
    log_info "Step 3/3: Deploying node groups..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-node-groups" \
        "cloudformation/03-node-groups.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=${ENVIRONMENT_NAME}"
    
    log_info "CloudFormation deployment complete!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Configure kubectl: aws eks update-kubeconfig --name ${ENVIRONMENT_NAME}-cluster --region ${AWS_REGION}"
    log_info "2. Install AWS Load Balancer Controller: ./scripts/install-alb-controller.sh"
    log_info "3. Deploy your microservices: kubectl apply -f kubernetes/"
}

# Run main function
main "$@"

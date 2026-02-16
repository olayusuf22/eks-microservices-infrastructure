#!/bin/bash

# Install AWS Load Balancer Controller on EKS
# This is required for Ingress resources to work with ALB

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-eks-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="${ENVIRONMENT_NAME}-cluster"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info "Installing AWS Load Balancer Controller..."
log_info "Cluster: $CLUSTER_NAME"
log_info "Region: $AWS_REGION"

# Install eksctl if not present
if ! command -v eksctl &> /dev/null; then
    log_warn "eksctl not found. You may need to install it: https://eksctl.io/"
fi

# Install Helm if not present
if ! command -v helm &> /dev/null; then
    log_warn "Helm not found. Installing..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Update kubeconfig
log_info "Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# Create IAM OIDC provider if not exists
log_info "Checking OIDC provider..."
if ! eksctl utils associate-iam-oidc-provider \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --approve 2>/dev/null; then
    log_warn "OIDC provider already exists or eksctl not available"
fi

# Create service account with IAM role
log_info "Creating service account for AWS Load Balancer Controller..."
kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Get the IAM role ARN from CloudFormation outputs
ALB_CONTROLLER_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-eks-cluster" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AWSLoadBalancerControllerRoleArn'].OutputValue" \
    --output text)

log_info "IAM Role ARN: $ALB_CONTROLLER_ROLE_ARN"

# Annotate the service account
kubectl annotate serviceaccount aws-load-balancer-controller \
    -n kube-system \
    eks.amazonaws.com/role-arn="$ALB_CONTROLLER_ROLE_ARN" \
    --overwrite

# Add EKS Helm repository
log_info "Adding EKS Helm repository..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
log_info "Installing AWS Load Balancer Controller via Helm..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="$AWS_REGION" \
    --set vpcId=$(aws cloudformation describe-stacks \
        --stack-name "${ENVIRONMENT_NAME}-vpc" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='VPC'].OutputValue" \
        --output text)

# Wait for deployment
log_info "Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/aws-load-balancer-controller -n kube-system

log_info "AWS Load Balancer Controller installed successfully!"
log_info ""
log_info "Verify installation:"
log_info "kubectl get deployment -n kube-system aws-load-balancer-controller"

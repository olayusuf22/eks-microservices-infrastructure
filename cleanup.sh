#!/bin/bash

# Cleanup script for EKS infrastructure
# WARNING: This will delete ALL resources created by the deployment

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-eks-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm_deletion() {
    echo -e "${RED}WARNING: This will delete the following resources:${NC}"
    echo "  - All Kubernetes resources (pods, services, ingress, etc.)"
    echo "  - EKS node groups and cluster"
    echo "  - VPC, subnets, NAT gateways, and all networking"
    echo "  - All data will be PERMANENTLY lost"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled."
        exit 0
    fi
}

delete_kubernetes_resources() {
    log_info "Deleting Kubernetes resources..."
    
    # Update kubeconfig
    aws eks update-kubeconfig --name "${ENVIRONMENT_NAME}-cluster" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null || true
    
    # Delete ingress first (to remove ALBs)
    log_info "Deleting ingress resources..."
    kubectl delete -f kubernetes/ingress/ --ignore-not-found=true 2>/dev/null || true
    
    # Wait for ALBs to be deleted
    log_warn "Waiting 60 seconds for load balancers to be deleted..."
    sleep 60
    
    # Delete deployments and services
    log_info "Deleting deployments and services..."
    kubectl delete -f kubernetes/deployments/ --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f kubernetes/services/ --ignore-not-found=true 2>/dev/null || true
    
    # Delete AWS Load Balancer Controller
    log_info "Deleting AWS Load Balancer Controller..."
    helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
    
    log_info "Kubernetes resources deleted."
}

delete_cloudformation_stack() {
    local stack_name=$1
    
    log_info "Deleting CloudFormation stack: $stack_name"
    
    if aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" &> /dev/null; then
        
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
        
        log_info "Waiting for stack deletion: $stack_name"
        aws cloudformation wait stack-delete-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" 2>/dev/null || log_warn "Stack deletion may have failed or timed out"
        
        log_info "Stack $stack_name deleted successfully"
    else
        log_warn "Stack $stack_name does not exist, skipping..."
    fi
}

check_remaining_resources() {
    log_info "Checking for remaining AWS resources..."
    
    # Check for remaining load balancers
    remaining_albs=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "LoadBalancers[?contains(LoadBalancerName, 'eks-microservices')].LoadBalancerName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_albs" ]; then
        log_warn "Remaining load balancers found: $remaining_albs"
        log_warn "These should be deleted manually if they persist"
    fi
    
    # Check for remaining security groups
    vpc_id=$(aws cloudformation describe-stacks \
        --stack-name "${ENVIRONMENT_NAME}-vpc" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "Stacks[0].Outputs[?OutputKey=='VPC'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$vpc_id" ]; then
        remaining_sgs=$(aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query "SecurityGroups[?GroupName!='default'].GroupId" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$remaining_sgs" ]; then
            log_warn "Remaining security groups in VPC: $remaining_sgs"
        fi
    fi
}

main() {
    log_warn "EKS Infrastructure Cleanup Script"
    log_warn "Environment: $ENVIRONMENT_NAME"
    log_warn "Region: $AWS_REGION"
    echo ""
    
    confirm_deletion
    
    log_info "Starting cleanup process..."
    
    # Step 1: Delete Kubernetes resources
    delete_kubernetes_resources
    
    # Step 2: Additional wait for ALB cleanup
    log_warn "Waiting additional 30 seconds to ensure load balancers are fully deleted..."
    sleep 30
    
    # Step 3: Delete CloudFormation stacks in reverse order
    delete_cloudformation_stack "${ENVIRONMENT_NAME}-node-groups"
    delete_cloudformation_stack "${ENVIRONMENT_NAME}-eks-cluster"
    delete_cloudformation_stack "${ENVIRONMENT_NAME}-vpc"
    
    # Step 4: Check for remaining resources
    check_remaining_resources
    
    log_info "Cleanup complete!"
    log_info ""
    log_info "If you encounter errors about resources still in use:"
    log_info "1. Wait a few more minutes for AWS to finish cleanup"
    log_info "2. Check the AWS Console for stuck resources"
    log_info "3. Manually delete load balancers and security groups if needed"
    log_info "4. Re-run this script"
}

main "$@"

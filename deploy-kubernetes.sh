#!/bin/bash

# Deploy Kubernetes manifests for microservices

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-eks-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${ENVIRONMENT_NAME}-cluster"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Update kubeconfig
log_info "Updating kubeconfig for cluster: $CLUSTER_NAME"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# Verify cluster connection
log_info "Verifying cluster connection..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to cluster. Please check your AWS credentials and cluster status."
    exit 1
fi

log_info "Connected to cluster: $(kubectl config current-context)"

# Create namespace if needed (using default for now)
log_info "Using namespace: default"

# Deploy services first
log_info "Deploying services..."
kubectl apply -f kubernetes/services/services.yaml

# Deploy deployments
log_info "Deploying microservices..."
for deployment in kubernetes/deployments/*.yaml; do
    log_info "Applying: $deployment"
    kubectl apply -f "$deployment"
done

# Wait for deployments to be ready
log_info "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment --all -n default || log_warn "Some deployments may not be ready yet"

# Deploy ingress
log_info "Deploying ingress..."
kubectl apply -f kubernetes/ingress/ingress.yaml

# Show deployment status
log_info ""
log_info "Deployment complete! Current status:"
log_info ""
kubectl get deployments -n default
log_info ""
kubectl get services -n default
log_info ""
kubectl get ingress -n default
log_info ""

# Get load balancer URL
log_info "Waiting for load balancer to be provisioned (this may take a few minutes)..."
sleep 30

ALB_URL=$(kubectl get ingress main-ingress -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not ready yet")

if [ "$ALB_URL" != "Not ready yet" ]; then
    log_info "Load Balancer URL: http://$ALB_URL"
    log_info "Update your DNS to point to this ALB"
else
    log_warn "Load balancer is still provisioning. Check status with: kubectl get ingress -n default"
fi

log_info ""
log_info "Useful commands:"
log_info "  View pods: kubectl get pods -n default"
log_info "  View logs: kubectl logs -f deployment/<deployment-name> -n default"
log_info "  Scale deployment: kubectl scale deployment/<deployment-name> --replicas=5 -n default"
log_info "  Port forward: kubectl port-forward service/<service-name> 8080:80 -n default"

# Quick Start Guide - EKS Microservices Deployment

## TL;DR - Get Running in 5 Commands

If you're experienced with AWS/Kubernetes and just want to get started:

```bash
# 1. Deploy infrastructure (30-45 minutes)
./scripts/deploy-infrastructure.sh

# 2. Configure kubectl
aws eks update-kubeconfig --name eks-prod-cluster --region us-east-1

# 3. Install AWS Load Balancer Controller (5 minutes)
./scripts/install-alb-controller.sh

# 4. Update deployment images with your ECR URLs
# Edit kubernetes/deployments/*.yaml files

# 5. Deploy your microservices
./scripts/deploy-kubernetes.sh
```

## Step-by-Step for Beginners

### Prerequisites Checklist

- [ ] AWS account with admin access
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] kubectl installed
- [ ] Helm installed
- [ ] Docker images ready in ECR

### 1. Prepare Your Container Images

First, create ECR repositories and push your images:

```bash
# Set your AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

# Create repositories
aws ecr create-repository --repository-name frontend --region $AWS_REGION
aws ecr create-repository --repository-name backend --region $AWS_REGION
aws ecr create-repository --repository-name api-gateway --region $AWS_REGION

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push your images (example for frontend)
docker build -t frontend:latest ./your-frontend-code
docker tag frontend:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/frontend:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/frontend:latest

# Repeat for backend and api-gateway
```

### 2. Update Kubernetes Manifests

Edit the deployment files and replace `<YOUR_ECR_REPO>` with your actual ECR repository URLs:

```bash
# In kubernetes/deployments/frontend-deployment.yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/frontend:latest

# In kubernetes/deployments/backend-deployment.yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/backend:latest

# In kubernetes/deployments/api-gateway-deployment.yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/api-gateway:latest
```

### 3. Deploy Infrastructure

Run the deployment script:

```bash
cd eks-cft-project
./scripts/deploy-infrastructure.sh
```

**Wait time:** 30-45 minutes

You can monitor progress in the AWS CloudFormation console.

### 4. Configure kubectl

Once deployment completes:

```bash
aws eks update-kubeconfig --name eks-prod-cluster --region us-east-1

# Verify it works
kubectl get nodes
```

You should see 3 nodes in Ready state.

### 5. Install AWS Load Balancer Controller

```bash
./scripts/install-alb-controller.sh
```

**Wait time:** 2-3 minutes

Verify:
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 6. Deploy Your Microservices

```bash
./scripts/deploy-kubernetes.sh
```

**Wait time:** 5-10 minutes

### 7. Get Your Load Balancer URL

```bash
kubectl get ingress main-ingress
```

Wait until the ADDRESS column shows an ALB URL (may take 5-10 minutes).

### 8. Test Your Application

```bash
# Get the ALB URL
export ALB_URL=$(kubectl get ingress main-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test frontend
curl http://$ALB_URL

# Test API (if using path-based routing)
curl http://$ALB_URL/api/health
```

## Common First-Time Issues

### Issue: Pods in ImagePullBackOff

**Cause:** ECR permissions or wrong image URL

**Fix:**
```bash
# Check pod events
kubectl describe pod <pod-name>

# Verify ECR repository exists
aws ecr describe-repositories --region us-east-1

# Ensure node role has ECR read permissions (already configured in templates)
```

### Issue: Ingress Not Creating ALB

**Cause:** AWS Load Balancer Controller not running

**Fix:**
```bash
# Check controller status
kubectl get pods -n kube-system | grep aws-load-balancer

# Check logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Reinstall if needed
./scripts/install-alb-controller.sh
```

### Issue: Can't Connect to Cluster

**Cause:** Wrong kubeconfig or AWS credentials

**Fix:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Re-configure kubectl
aws eks update-kubeconfig --name eks-prod-cluster --region us-east-1

# Test connection
kubectl cluster-info
```

## Environment Customization

For different environments (dev, staging, prod), modify `config.env`:

```bash
# Development
ENVIRONMENT_NAME="eks-dev"
NODE_MIN_SIZE=1
NODE_DESIRED_SIZE=2
NODE_MAX_SIZE=3
NODE_INSTANCE_TYPE="t3.small"

# Production
ENVIRONMENT_NAME="eks-prod"
NODE_MIN_SIZE=3
NODE_DESIRED_SIZE=5
NODE_MAX_SIZE=10
NODE_INSTANCE_TYPE="m5.large"
```

## Monitoring Your Deployment

```bash
# Watch pod status
watch kubectl get pods

# Check resource usage
kubectl top nodes
kubectl top pods

# View logs
kubectl logs -f deployment/frontend
kubectl logs -f deployment/backend

# Check events for issues
kubectl get events --sort-by='.lastTimestamp'
```

## Scaling

### Manual Scaling

```bash
# Scale a deployment
kubectl scale deployment/backend --replicas=10

# Verify
kubectl get deployment backend
```

### Auto-scaling (Already Configured)

HPA is automatically configured. Check status:

```bash
kubectl get hpa
```

## Cost Estimate

Approximate monthly costs (us-east-1):

- **EKS Cluster:** $73/month
- **EC2 Nodes (3x t3.medium):** ~$90/month
- **NAT Gateways (3):** ~$100/month
- **ALB:** ~$20/month
- **Data transfer:** Variable
- **Total:** ~$283/month minimum

To reduce costs:
- Use 1 NAT Gateway instead of 3 (dev only)
- Use smaller instance types
- Enable cluster autoscaler to scale to 0 when idle

## Next Steps

1. **Add SSL/TLS:** Request ACM certificate and update ingress
2. **Set up CI/CD:** Automate deployments with GitHub Actions
3. **Add monitoring:** Install Prometheus + Grafana
4. **Configure logging:** Set up FluentBit
5. **Implement GitOps:** Use ArgoCD for declarative deployment

## Getting Help

1. Check the main [README.md](README.md) for detailed documentation
2. Review CloudFormation events in AWS Console
3. Check pod logs: `kubectl logs <pod-name>`
4. Describe resources: `kubectl describe pod/service/deployment <name>`

## Cleanup

When you're done testing:

```bash
./scripts/cleanup.sh
```

**This will delete everything!** Make sure you have backups.

---

**Congratulations!** You now have a production-ready EKS cluster running your microservices! 🎉

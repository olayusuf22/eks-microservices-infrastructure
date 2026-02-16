# EKS Microservices Infrastructure

A production-ready Amazon EKS (Elastic Kubernetes Service) infrastructure deployed using AWS CloudFormation, featuring automated deployment of a scalable microservices architecture with MongoDB persistence, load balancing, and high availability.

## 🏗️ Architecture Overview

This project implements a complete cloud-native infrastructure on AWS with the following components:

### Infrastructure Components
- **VPC**: Custom Virtual Private Cloud with 6 subnets across 3 availability zones
  - 3 Public subnets for load balancers and NAT gateways
  - 3 Private subnets for application workloads
  - Internet Gateway for public connectivity
  - 3 NAT Gateways for high availability
- **EKS Cluster**: Managed Kubernetes cluster (v1.28+)
- **Node Group**: Auto-scaling group of EC2 instances (t3.medium)
  - Min: 2 nodes
  - Desired: 3 nodes
  - Max: 6 nodes
- **EBS CSI Driver**: For persistent volume support
- **Application Load Balancer**: Internet-facing load balancer for external traffic

### Application Components
- **MongoDB**: StatefulSet with 10GB persistent storage
- **Backend Service**: 3 replicas with ClusterIP service
- **Frontend Service**: 3 replicas with LoadBalancer service
- **Ingress**: Traffic routing for microservices

## 📋 Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Docker Desktop (optional, for custom images)
- AWS Account with permissions for:
  - EKS
  - EC2
  - VPC
  - CloudFormation
  - IAM
  - EBS

## 🚀 Quick Start

### 1. Deploy Infrastructure (CloudFormation)

Upload the CloudFormation templates in this order:

#### Step 1: VPC Stack
```bash
Stack Name: eks-vpc-stack
Template: 1-vpc-stack.yaml
Parameters: Use defaults (all CIDR ranges pre-configured)
```

#### Step 2: EKS Cluster Stack
```bash
Stack Name: eks-cluster-stack
Template: 2-eks-cluster-stack.yaml
Parameters: 
  - EnvironmentName: eks-prod
  - KubernetesVersion: 1.28
Capabilities: Check "I acknowledge that AWS CloudFormation might create IAM resources"
Wait Time: ~15 minutes
```

#### Step 3: Node Group Stack
```bash
Stack Name: eks-nodegroup-stack
Template: 3-eks-nodegroup-stack.yaml
Parameters:
  - NodeInstanceType: t3.medium
  - NodeAutoScalingGroupMinSize: 2
  - NodeAutoScalingGroupDesiredCapacity: 3
  - NodeAutoScalingGroupMaxSize: 6
Wait Time: ~5 minutes
```

### 2. Configure kubectl Access

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-prod --profile default

# Verify connection
kubectl get nodes
```

### 3. Grant IAM User Access

```bash
# Create access entry for your IAM user
aws eks create-access-entry \
  --cluster-name eks-prod \
  --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:user/YOUR_USERNAME \
  --region us-east-1

# Associate admin policy
aws eks associate-access-policy \
  --cluster-name eks-prod \
  --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:user/YOUR_USERNAME \
  --access-scope type=cluster \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --region us-east-1
```

### 4. Install EBS CSI Driver

```bash
aws eks create-addon \
  --cluster-name eks-prod \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1
```

### 5. Tag Public Subnets for LoadBalancer

```bash
# Get subnet IDs
aws ec2 describe-subnets --region us-east-1 \
  --filters "Name=tag:Name,Values=eks-prod-public-subnet-*" \
  --query "Subnets[].SubnetId" --output table

# Tag subnets (replace with your actual subnet IDs)
aws ec2 create-tags \
  --resources subnet-XXXXX subnet-YYYYY subnet-ZZZZZ \
  --tags Key=kubernetes.io/role/elb,Value=1 \
  --region us-east-1

aws ec2 create-tags \
  --resources subnet-XXXXX subnet-YYYYY subnet-ZZZZZ \
  --tags Key=kubernetes.io/cluster/eks-prod,Value=shared \
  --region us-east-1
```

### 6. Deploy Kubernetes Applications

```bash
# Deploy all components
kubectl apply -f namespace.yaml
kubectl apply -f mongodb-statefulset.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f ingress.yaml

# Verify deployments
kubectl get pods -n microservices
kubectl get svc -n microservices
```

### 7. Access Your Application

```bash
# Get LoadBalancer URL
kubectl get svc frontend -n microservices

# Access the application
# http://<EXTERNAL-IP>
```

## 📁 Project Structure

```
eks-cft-project/
├── cloudformation/
│   ├── 1-vpc-stack.yaml              # VPC and networking
│   ├── 2-eks-cluster-stack.yaml      # EKS cluster and IAM roles
│   ├── 3-eks-nodegroup-stack.yaml    # Worker nodes
│   ├── namespace.yaml                 # Kubernetes namespace
│   ├── mongodb-statefulset.yaml       # MongoDB database
│   ├── backend-deployment.yaml        # Backend service
│   ├── frontend-deployment.yaml       # Frontend service
│   └── ingress.yaml                   # Ingress routing
├── config.env                         # Environment configuration
├── README.md                          # This file
└── QUICKSTART.md                      # Quick reference guide
```

## 🔧 Configuration

### Network Configuration (VPC)
- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24
- **Availability Zones**: 3 (us-east-1a, us-east-1b, us-east-1c)

### EKS Cluster
- **Name**: eks-prod
- **Kubernetes Version**: 1.28+
- **Endpoint Access**: Public and Private
- **Logging**: Enabled (API, Audit, Authenticator, Controller Manager, Scheduler)

### Node Group
- **Instance Type**: t3.medium
- **Min Nodes**: 2
- **Desired Nodes**: 3
- **Max Nodes**: 6
- **Volume Size**: 50GB (gp3, encrypted)
- **AMI**: Amazon Linux 2 (EKS optimized)

### Application Resources
- **MongoDB**: 1 replica, 10GB persistent volume
- **Backend**: 3 replicas, 256Mi-512Mi memory
- **Frontend**: 3 replicas, 128Mi-256Mi memory

## 📊 Monitoring & Management

### View Cluster Resources
```bash
# All resources
kubectl get all -n microservices

# Pods
kubectl get pods -n microservices

# Services
kubectl get svc -n microservices

# Persistent Volumes
kubectl get pvc -n microservices
```

### View Logs
```bash
# Backend logs
kubectl logs -f deployment/backend -n microservices

# Frontend logs
kubectl logs -f deployment/frontend -n microservices

# MongoDB logs
kubectl logs mongodb-0 -n microservices
```

### Scale Applications
```bash
# Scale backend
kubectl scale deployment backend --replicas=5 -n microservices

# Scale frontend
kubectl scale deployment frontend --replicas=5 -n microservices
```

### Update Application Images
```bash
# Update backend image
kubectl set image deployment/backend backend=YOUR_REGISTRY/backend:v2 -n microservices

# Update frontend image
kubectl set image deployment/frontend frontend=YOUR_REGISTRY/frontend:v2 -n microservices
```

## 🔒 Security Features

- **IAM Roles for Service Accounts (IRSA)**: OIDC provider configured
- **Network Segmentation**: Private subnets for workloads, public for LBs
- **Encrypted EBS Volumes**: All persistent data encrypted at rest
- **Security Groups**: Cluster control plane security group
- **Private API Endpoint**: Available for enhanced security
- **IMDSv2**: Required on all EC2 instances

## 💰 Cost Optimization

Estimated monthly costs (us-east-1):
- **EKS Cluster**: ~$73/month
- **3x t3.medium nodes**: ~$100/month
- **3x NAT Gateways**: ~$100/month
- **EBS Volumes**: ~$5/month
- **Load Balancer**: ~$20/month
- **Data Transfer**: Variable

**Total**: ~$300-350/month

### Cost Saving Tips
- Use Spot instances for non-critical workloads
- Reduce NAT gateways to 1 for dev/test
- Use smaller instance types for testing
- Enable cluster autoscaler for dynamic scaling
- Delete resources when not in use

## 🧹 Cleanup

To delete all resources and avoid charges:

```bash
# Delete Kubernetes resources
kubectl delete namespace microservices

# Delete CloudFormation stacks (in reverse order)
aws cloudformation delete-stack --stack-name eks-nodegroup-stack --region us-east-1
# Wait for completion (~5 minutes)

aws cloudformation delete-stack --stack-name eks-cluster-stack --region us-east-1
# Wait for completion (~10 minutes)

aws cloudformation delete-stack --stack-name eks-vpc-stack --region us-east-1
# Wait for completion (~5 minutes)

# Verify all resources deleted
aws cloudformation list-stacks --region us-east-1 \
  --stack-status-filter DELETE_COMPLETE
```

## 🐛 Troubleshooting

### Pods Not Starting
```bash
# Describe pod
kubectl describe pod POD_NAME -n microservices

# Check events
kubectl get events -n microservices --sort-by='.lastTimestamp'
```

### LoadBalancer Pending
```bash
# Verify subnet tags
aws ec2 describe-subnets --subnet-ids SUBNET_ID

# Required tags:
# - kubernetes.io/role/elb = 1
# - kubernetes.io/cluster/eks-prod = shared
```

### Cannot Access Cluster
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-prod

# Verify IAM permissions
aws sts get-caller-identity

# Check access entry
aws eks list-access-entries --cluster-name eks-prod --region us-east-1
```

### MongoDB Storage Issues
```bash
# Verify EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi

# Check PVC status
kubectl get pvc -n microservices
```

## 📚 Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)

## 🤝 Contributing

This is a learning/demonstration project. Feel free to:
- Fork and customize for your needs
- Report issues or suggest improvements
- Share your deployment experiences

## 📝 License

This project is provided as-is for educational and demonstration purposes.

## 👨‍💻 Author

Created as a demonstration of enterprise-grade AWS EKS infrastructure deployment using Infrastructure as Code (IaC) principles.

## 🎯 Key Achievements

✅ Automated infrastructure deployment with CloudFormation
✅ High availability across 3 availability zones
✅ Auto-scaling node groups (2-6 nodes)
✅ Persistent storage with EBS CSI driver
✅ Production-ready networking with NAT gateways
✅ Secure IAM roles and OIDC integration
✅ Load-balanced, publicly accessible application
✅ Comprehensive monitoring and logging enabled

---

**Status**: ✅ Deployed and Operational

**Last Updated**: February 2026

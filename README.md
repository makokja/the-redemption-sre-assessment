# The Redemption - SRE Assessment Solution

## Overview

This repository contains a production-ready infrastructure solution for "The Redemption" microservice - a business-critical application handling global hotel point deductions on AWS EKS.

**Note**: This is an infrastructure/SRE assessment. The actual application code is not included - only the deployment infrastructure, Kubernetes manifests, and operational tooling.

## Architecture Highlights

- **Zero Downtime**: Multi-AZ deployment with automatic failover
- **Auto-Scaling**: Handles 10x traffic spikes automatically
- **Security**: Defense-in-depth with WAF, Network Policies, and encryption
- **Observability**: Comprehensive monitoring with CloudWatch, Prometheus, and Grafana
- **Infrastructure as Code**: Fully automated with Terraform and Helm

## Repository Structure

```
the-redemption-sre-assessment/
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                  # Main Terraform configuration
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   ├── modules/
│   │   ├── vpc/                 # VPC with Multi-AZ networking
│   │   ├── eks/                 # EKS cluster configuration
│   │   ├── security/            # Security groups, WAF, KMS
│   │   └── monitoring/          # CloudWatch, alarms, dashboards
│   └── environments/
│       └── production/          # Production environment configs
├── k8s/                         # Kubernetes manifests
│   ├── argocd/                  # ArgoCD GitOps configuration
│   │   ├── application.yaml     # ArgoCD Application manifest
│   │   └── README.md            # GitOps deployment guide
│   └── helm/                    # Helm charts
│       └── redemption/          # Redemption service Helm chart
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
├── app/                         # Application placeholder (not included)
├── docs/                        # Documentation
│   └── design-document.md       # Comprehensive design document
├── diagrams/                    # Architecture diagrams
│   └── architecture-description.md  # Architecture diagram
├── QUICKSTART.md                # Quick deployment guide
└── README.md                    # This file
```

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.0

## Quick Start

### 1. Infrastructure Deployment

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the infrastructure
terraform apply

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name the-redemption-cluster
```

### 2. Secrets Management (AWS Secrets Manager)

**Recommended**: Use AWS Secrets Manager for secure credential storage instead of hardcoded secrets.

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace

# Create secrets in AWS Secrets Manager
./scripts/setup-secrets-manager.sh

# Apply External Secrets configuration
kubectl apply -f k8s/external-secrets/

# Verify secrets are synced
kubectl get externalsecret -n redemption
kubectl get secret redemption-secrets -n redemption
```

See [`k8s/external-secrets/README.md`](k8s/external-secrets/README.md) for detailed documentation.

### 3. Application Deployment

```bash
# Navigate to Helm chart directory
cd k8s/helm/redemption

# Update values.yaml with your configurations
# - ECR repository URL (replace ACCOUNT_ID)
# - IAM role ARNs

# Install the Helm chart (with External Secrets enabled)
helm install redemption . -n redemption --create-namespace

# Verify deployment
kubectl get pods -n redemption
kubectl get hpa -n redemption
```

**Note**: You'll need to build and push your application container image to ECR before the pods can start. See [`app/README.md`](app/README.md) for application requirements.

### 4. Verify Auto-Scaling

```bash
# Watch HPA status
kubectl get hpa -n redemption --watch

# Generate load to test scaling
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh
# Inside the pod:
while true; do wget -q -O- http://redemption-service.redemption.svc.cluster.local; done
```

## Key Features

### A. Compute & Architecture

- **Multi-AZ EKS Cluster**: Deployed across 3 availability zones
- **Node Groups**:
  - General purpose nodes (t3.large) for system workloads
  - High-performance nodes (c5.2xlarge) with Spot instances for cost optimization
- **Pod Anti-Affinity**: Ensures pods are distributed across nodes and AZs
- **Zero Downtime Deployments**: Rolling updates with maxUnavailable=0

### B. Scalability Strategy

- **Horizontal Pod Autoscaler (HPA)**:
  - Min: 3 replicas, Max: 50 replicas
  - CPU target: 70%, Memory target: 80%
  - Aggressive scale-up (100% in 15s) for flash sales
  - Conservative scale-down (10% per minute) to prevent flapping

- **Karpenter**:
  - Just-in-time node provisioning (<30 seconds)
  - Bin-packing optimization for cost efficiency
  - Spot instance support (70% spot, 30% on-demand)

- **Application Load Balancer**:
  - Cross-zone load balancing enabled
  - Connection draining for graceful shutdowns

### C. Security & Networking

- **Network Segmentation**:
  - Public subnets for ALB
  - Private subnets for EKS nodes and data stores
  - Multi-AZ NAT Gateways for high availability

- **Security Layers**:
  - AWS WAF with managed rule sets (OWASP Top 10, rate limiting)
  - Network Policies for pod-to-pod communication
  - Security Groups with least privilege access
  - KMS encryption for secrets and EBS volumes
  - Pod Security Context (non-root, read-only filesystem)

- **Secrets Management**:
  - AWS Secrets Manager for sensitive data
  - IAM Roles for Service Accounts (IRSA) for pod-level permissions

### D. Reliability & Observability

- **Health Checks**:
  - Liveness probes to restart unhealthy pods
  - Readiness probes to control traffic routing
  - ALB health checks with configurable thresholds

- **Monitoring Stack**:
  - CloudWatch Container Insights for cluster metrics
  - Prometheus for application metrics
  - CloudWatch Dashboards for visualization
  - SNS alerts for critical events

- **Logging**:
  - Centralized logging to CloudWatch Logs
  - VPC Flow Logs for network traffic analysis
  - EKS control plane logs

- **Disaster Recovery**:
  - RDS Multi-AZ with automated backups
  - ElastiCache Redis with automatic failover
  - Pod Disruption Budgets (min 2 available)

### E. Operations

#### Day 2 Operations

1. **Automated Deployments**:
   - GitOps workflow with ArgoCD (see [`k8s/argocd/`](k8s/argocd/))
   - Helm for application lifecycle management
   - Terraform for infrastructure changes

2. **Monitoring & Alerting**:
   - Pre-configured CloudWatch alarms for CPU, memory, errors
   - SNS notifications to SRE team
   - Prometheus metrics for custom application metrics

3. **Cost Optimization**:
   - Spot instances for burst capacity
   - Cluster autoscaler to right-size infrastructure
   - Resource requests/limits to prevent over-provisioning

4. **Backup & Recovery**:
   - Automated RDS snapshots (7-day retention)
   - Velero for Kubernetes backup (recommended)
   - Infrastructure state in S3 with versioning

## Team Delegation Plan

### Senior Engineer (Lead)
**Responsibilities**:
- Architecture design and review
- Terraform module development (EKS, Security)
- CI/CD pipeline setup
- Production deployment and validation
- Mentoring junior engineers

**Tasks**:
- [ ] Design and implement EKS cluster module
- [ ] Configure security layers (WAF, Security Groups, KMS)
- [ ] Set up monitoring and alerting
- [ ] Review and approve all PRs
- [ ] Production deployment

**Estimated Time**: 3-4 days

### Junior Engineer 1
**Responsibilities**:
- VPC and networking setup
- Database and cache infrastructure
- Documentation

**Tasks**:
- [ ] Implement VPC module with multi-AZ networking
- [ ] Configure RDS PostgreSQL with Multi-AZ
- [ ] Set up ElastiCache Redis cluster
- [ ] Write deployment documentation
- [ ] Create runbooks for common operations

**Estimated Time**: 2-3 days

### Junior Engineer 2
**Responsibilities**:
- Kubernetes manifests and Helm charts
- Application deployment
- Testing and validation

**Tasks**:
- [ ] Create Helm chart for redemption service
- [ ] Configure HPA and PDB
- [ ] Set up Prometheus monitoring
- [ ] Perform load testing
- [ ] Document scaling behavior

**Estimated Time**: 2-3 days

## Deployment Checklist

- [ ] Update `terraform/variables.tf` with your AWS account details
- [ ] Create S3 bucket for Terraform state
- [ ] Create DynamoDB table for state locking
- [ ] Update `k8s/helm/redemption/values.yaml` with:
  - [ ] ECR repository URL (replace ACCOUNT_ID)
  - [ ] IAM role ARNs
  - [ ] Alert email address
- [ ] Build and push your application Docker image to ECR
- [ ] Apply Terraform infrastructure
- [ ] Deploy application with Helm
- [ ] Verify auto-scaling behavior
- [ ] Configure DNS for ALB
- [ ] Set up CI/CD pipeline

## Monitoring & Alerts

### CloudWatch Dashboards
Access the dashboard at: AWS Console → CloudWatch → Dashboards → `the-redemption-cluster-dashboard`

### Key Metrics
- Node CPU/Memory utilization
- Pod restart count
- ALB target response time
- HTTP 2XX/4XX/5XX counts
- HPA current/desired replicas

### Alert Thresholds
- CPU > 80% for 10 minutes
- Memory > 80% for 10 minutes
- Pod restarts > 5 in 5 minutes
- Response time > 1 second
- 5XX errors > 10 per minute

## Troubleshooting

### Pods not scaling
```bash
# Check HPA status
kubectl describe hpa redemption -n redemption

# Check metrics server
kubectl top nodes
kubectl top pods -n redemption

# Check cluster autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler
```

### High latency
```bash
# Check pod logs
kubectl logs -n redemption -l app=redemption --tail=100

# Check database connections
kubectl exec -it -n redemption <pod-name> -- netstat -an | grep 5432

# Check Redis connections
kubectl exec -it -n redemption <pod-name> -- netstat -an | grep 6379
```

### Deployment failures
```bash
# Check deployment status
kubectl rollout status deployment/redemption -n redemption

# Check pod events
kubectl describe pod -n redemption <pod-name>

# Rollback if needed
kubectl rollout undo deployment/redemption -n redemption
```

## Cost Estimation

### Monthly Infrastructure Costs (Approximate)

- **EKS Control Plane**: $73/month
- **EC2 Instances** (3 t3.large + 2 c5.2xlarge): ~$400/month
- **RDS PostgreSQL** (db.r6g.xlarge Multi-AZ): ~$500/month
- **ElastiCache Redis** (cache.r6g.large x3): ~$400/month
- **ALB**: ~$25/month + data transfer
- **NAT Gateways** (3 AZs): ~$100/month
- **CloudWatch & Monitoring**: ~$50/month
- **Data Transfer**: Variable based on traffic

**Total**: ~$1,550/month (baseline) + scaling costs during peak traffic

## Security Considerations

1. **Secrets**: Never commit secrets to Git. Use AWS Secrets Manager or External Secrets Operator
2. **IAM**: Follow least privilege principle for all IAM roles
3. **Network**: Keep databases in private subnets with no public access
4. **Updates**: Regularly update EKS version and node AMIs
5. **Scanning**: Implement container image scanning in CI/CD pipeline

## Contributing

1. Create a feature branch
2. Make changes and test locally
3. Submit PR with description
4. Wait for code review from Senior Engineer
5. Merge after approval


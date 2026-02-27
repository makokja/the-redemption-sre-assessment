# Quick Start Guide - The Redemption

## Prerequisites Checklist

- [ ] AWS Account with admin access
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Terraform >= 1.5.0 installed
- [ ] kubectl >= 1.28 installed
- [ ] Helm >= 3.0 installed
- [ ] Docker installed (for building images)

## Step-by-Step Deployment

### Step 1: Prepare AWS Account (5 minutes)

```bash
# Set your AWS region
export AWS_REGION=us-east-1

# Create S3 bucket for Terraform state
aws s3 mb s3://the-redemption-terraform-state --region $AWS_REGION

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket the-redemption-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION

# Create ECR repository
aws ecr create-repository \
  --repository-name redemption \
  --region $AWS_REGION
```

### Step 2: Configure Terraform Variables (2 minutes)

```bash
cd terraform

# Create terraform.tfvars file
cat > terraform.tfvars <<EOF
aws_region           = "us-east-1"
environment          = "production"
project_name         = "the-redemption"
alert_email          = "your-email@example.com"
eks_cluster_version  = "1.28"
EOF
```

### Step 3: Deploy Infrastructure (20-30 minutes)

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply infrastructure
terraform apply tfplan

# Save outputs
terraform output > ../outputs.txt
```

### Step 4: Configure kubectl (1 minute)

```bash
# Get cluster name from outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Configure kubectl
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify connection
kubectl get nodes
kubectl get pods --all-namespaces
```

### Step 5: Build and Push Docker Image (5 minutes)

```bash
# Get ECR repository URL
ECR_REPO=$(aws ecr describe-repositories --repository-names redemption --query 'repositories[0].repositoryUri' --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build your application image (example)
# Replace with your actual Dockerfile location
docker build -t redemption:latest .

# Tag image
docker tag redemption:latest $ECR_REPO:latest

# Push to ECR
docker push $ECR_REPO:latest
```

### Step 6: Setup AWS Secrets Manager (5 minutes)

**Recommended**: Use AWS Secrets Manager for secure credential storage.

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace

# Wait for operator to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=external-secrets \
  -n external-secrets-system --timeout=120s

# Create secrets in AWS Secrets Manager
cd ../../../
./scripts/setup-secrets-manager.sh

# Apply External Secrets configuration
kubectl apply -f k8s/external-secrets/

# Verify secrets are synced
kubectl get secretstore -n redemption
kubectl get externalsecret -n redemption
kubectl get secret redemption-secrets -n redemption
```

### Step 7: Update Helm Values (2 minutes)

```bash
cd k8s/helm/redemption

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update values.yaml with your account ID
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" values.yaml
```

### Step 8: Deploy Application (5 minutes)

```bash
# Install Helm chart (External Secrets enabled by default)
helm install redemption . \
  -n redemption \
  --create-namespace

# Watch deployment
kubectl get pods -n redemption --watch

# Check HPA
kubectl get hpa -n redemption

# Get service endpoint
kubectl get ingress -n redemption
```

### Step 9: Verify Deployment (5 minutes)

```bash
# Check pod status
kubectl get pods -n redemption

# Check logs
kubectl logs -n redemption -l app=redemption --tail=50

# Test health endpoint
POD_NAME=$(kubectl get pods -n redemption -l app=redemption -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n redemption $POD_NAME 8080:8080 &
curl http://localhost:8080/health

# Check metrics
curl http://localhost:8080/metrics
```

### Step 10: Load Testing (Optional, 10 minutes)

```bash
# Install load testing tool
kubectl run -i --tty load-generator --rm --image=williamyeh/hey --restart=Never -- /bin/sh

# Inside the pod, run load test
hey -z 60s -c 50 http://redemption-service.redemption.svc.cluster.local

# Watch HPA scale
kubectl get hpa -n redemption --watch
```

### Step 11: Configure Monitoring (5 minutes)

```bash
# Access CloudWatch Dashboard
echo "CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=the-redemption-cluster-dashboard"

# Port-forward to Prometheus (if deployed)
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
echo "Prometheus: http://localhost:9090"

# Verify alerts are configured
aws sns list-subscriptions --region $AWS_REGION
```

## Verification Checklist

- [ ] All nodes are in Ready state
- [ ] All pods are Running (0/X restarts)
- [ ] HPA shows current metrics
- [ ] Ingress has an address assigned
- [ ] Health check returns 200 OK
- [ ] Metrics endpoint is accessible
- [ ] CloudWatch dashboard shows data
- [ ] SNS subscription is confirmed

## Common Issues & Solutions

### Issue: Pods stuck in Pending
```bash
# Check events
kubectl describe pod -n redemption <pod-name>

# Check node capacity
kubectl describe nodes

# Solution: Cluster autoscaler will add nodes automatically
# Wait 2-3 minutes or manually scale node group
```

### Issue: Cannot pull image from ECR
```bash
# Verify IAM role for nodes has ECR permissions
aws iam get-role --role-name the-redemption-cluster-node-role

# Solution: Ensure AmazonEC2ContainerRegistryReadOnly policy is attached
```

### Issue: Database connection failed
```bash
# Check security group rules
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=the-redemption-rds-sg"

# Verify RDS endpoint
aws rds describe-db-instances --db-instance-identifier the-redemption-db

# Solution: Ensure node security group can access RDS security group on port 5432
```

### Issue: HPA not scaling
```bash
# Check metrics server
kubectl top nodes
kubectl top pods -n redemption

# Check HPA status
kubectl describe hpa -n redemption redemption

# Solution: Ensure metrics-server is installed and running
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Cleanup (When Done Testing)

```bash
# Delete Helm release
helm uninstall redemption -n redemption

# Delete namespace
kubectl delete namespace redemption

# Destroy infrastructure
cd terraform
terraform destroy

# Delete S3 bucket (after emptying)
aws s3 rm s3://the-redemption-terraform-state --recursive
aws s3 rb s3://the-redemption-terraform-state

# Delete DynamoDB table
aws dynamodb delete-table --table-name terraform-state-lock
```

## Next Steps

1. **Set up CI/CD Pipeline**: Integrate with GitHub Actions or GitLab CI
2. **Configure GitOps**: Deploy ArgoCD (see [`k8s/argocd/README.md`](k8s/argocd/README.md))
3. **Enable Service Mesh**: Install Istio for advanced traffic management
4. **Implement Backup Strategy**: Set up Velero for Kubernetes backups
5. **Cost Optimization**: Review and implement Reserved Instances

## Optional: GitOps with ArgoCD

For continuous deployment from Git:

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Deploy application via ArgoCD
cd k8s/argocd
# Update repoURL in application.yaml first
kubectl apply -f application.yaml

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

See [`k8s/argocd/README.md`](k8s/argocd/README.md) for detailed instructions.

## Support

- Documentation: See `docs/design-document.md`
- Architecture: See `diagrams/architecture-description.md`
- Issues: Create GitHub issue or contact SRE team

## Estimated Total Time

- **First-time setup**: 60-90 minutes
- **Subsequent deployments**: 15-20 minutes

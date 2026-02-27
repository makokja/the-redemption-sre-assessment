# Karpenter Configuration for The Redemption

This directory contains Karpenter configuration for automatic, intelligent node provisioning in the EKS cluster.

## Overview

Karpenter is a flexible, high-performance Kubernetes cluster autoscaler that provisions right-sized compute resources in response to changing application load. Unlike Cluster Autoscaler, Karpenter provisions nodes directly without requiring pre-defined node groups.

## Files

- **`nodepool.yaml`**: Defines the NodePool with instance requirements, limits, and disruption policies
- **`ec2nodeclass.yaml`**: Defines the EC2NodeClass with AMI, subnets, security groups, and instance configuration
- **`karpenter-values.yaml`**: Helm values for Karpenter installation

## Key Features

### 1. **Just-in-Time Provisioning**
- Provisions nodes in <30 seconds based on pending pods
- No pre-warming or over-provisioning needed
- Right-sized instances for workload requirements

### 2. **Cost Optimization**
- **Spot Instance Support**: Mix of On-Demand (30%) and Spot (70%) for cost savings
- **Bin-packing**: Optimizes pod placement to minimize node count
- **Consolidation**: Automatically replaces nodes with cheaper options
- **Instance Diversity**: Uses multiple instance types (t3, m5, c5 families)

### 3. **High Availability**
- Multi-AZ node distribution
- Automatic node replacement on failure
- Disruption budgets to prevent mass disruptions

### 4. **Flash Sale Readiness**
- Aggressive scale-up (<30s) for traffic spikes
- Supports scaling from 3 to 50+ pods
- Automatic scale-down after traffic subsides

## Prerequisites

### 1. Install Karpenter

```bash
# Add Karpenter Helm repo
helm repo add karpenter https://charts.karpenter.sh
helm repo update

# Install Karpenter
helm upgrade --install karpenter karpenter/karpenter \
  --namespace karpenter --create-namespace \
  --values k8s/karpenter/karpenter-values.yaml \
  --wait
```

### 2. Tag Your Subnets

Karpenter discovers subnets using tags:

```bash
# Tag private subnets
aws ec2 create-tags \
  --resources subnet-xxxxx subnet-yyyyy subnet-zzzzz \
  --tags Key=karpenter.sh/discovery,Value=redemption-cluster
```

### 3. Tag Your Security Groups

```bash
# Tag node security group
aws ec2 create-tags \
  --resources sg-xxxxx \
  --tags Key=karpenter.sh/discovery,Value=redemption-cluster
```

### 4. Create IAM Role

The Karpenter controller needs an IAM role with permissions to launch EC2 instances. See Terraform configuration in `terraform/modules/karpenter/` (to be created).

## Configuration Details

### NodePool Configuration

```yaml
spec:
  requirements:
    - capacity-type: on-demand, spot (70% spot for cost savings)
    - instance-category: t, m, c (general purpose, compute optimized)
    - instance-generation: >4 (t3, m5, c5 and newer)
    - instance-size: large, xlarge, 2xlarge
  
  limits:
    cpu: 100 vCPUs
    memory: 400Gi
  
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
    expireAfter: 720h (30 days)
```

### EC2NodeClass Configuration

```yaml
spec:
  amiFamily: AL2 (Amazon Linux 2)
  blockDeviceMappings:
    - volumeSize: 100Gi
    - volumeType: gp3
    - encrypted: true
  metadataOptions:
    httpTokens: required (IMDSv2)
  detailedMonitoring: true
```

## Deployment

### Apply Karpenter Configuration

```bash
# Apply EC2NodeClass first
kubectl apply -f k8s/karpenter/ec2nodeclass.yaml

# Apply NodePool
kubectl apply -f k8s/karpenter/nodepool.yaml

# Verify
kubectl get nodepools
kubectl get ec2nodeclasses
```

### Monitor Karpenter

```bash
# Watch Karpenter logs
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter

# Check node provisioning
kubectl get nodes -l managed-by=karpenter

# View Karpenter metrics
kubectl port-forward -n karpenter svc/karpenter 8080:8080
# Open http://localhost:8080/metrics
```

## Scaling Behavior

### Normal Traffic (Baseline)
- **3 pods** across 3 AZs
- **3 nodes** (1 per AZ, t3.large)
- Cost: ~$150/month

### Flash Sale (10x Traffic Spike)
- **50 pods** (HPA scales up in 15s)
- **15-20 nodes** (Karpenter provisions in <30s)
- Mix of On-Demand and Spot instances
- Cost: ~$500/month during spike

### Post-Flash Sale
- Karpenter consolidates nodes within 30s
- Scales down to baseline within 5 minutes
- Automatic cost optimization

## Cost Comparison

| Scenario | Cluster Autoscaler | Karpenter | Savings |
|----------|-------------------|-----------|---------|
| Baseline | $180/month | $150/month | 17% |
| Flash Sale | $600/month | $400/month | 33% |
| Scale-up Time | 1-2 minutes | <30 seconds | 4x faster |
| Scale-down Time | 10 minutes | 30 seconds | 20x faster |

## Disruption Management

### Consolidation
- Automatically moves pods to fewer, cheaper nodes
- Respects Pod Disruption Budgets (PDB)
- Gradual rollout (10% of nodes at a time)

### Expiration
- Nodes expire after 30 days
- Forces regular updates and security patches
- Prevents configuration drift

### Scheduled Maintenance
- No disruptions during business hours (9 AM - 5 PM weekdays)
- Allows consolidation outside peak times

## Troubleshooting

### Pods Stuck in Pending

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i error

# Check NodePool status
kubectl describe nodepool redemption-nodepool

# Check if subnets/security groups are tagged
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=redemption-cluster"
```

### Nodes Not Scaling Down

```bash
# Check for pods preventing scale-down
kubectl get pods -A -o wide | grep <node-name>

# Check for PDBs
kubectl get pdb -A

# Check Karpenter disruption settings
kubectl get nodepool redemption-nodepool -o yaml | grep -A 10 disruption
```

### High Costs

```bash
# Check instance types being used
kubectl get nodes -l managed-by=karpenter -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type

# Verify Spot usage
kubectl get nodes -l managed-by=karpenter -o custom-columns=NAME:.metadata.name,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type

# Check for consolidation
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep consolidation
```

## Best Practices

1. **Always use Pod Disruption Budgets (PDB)** to prevent service disruptions
2. **Set appropriate resource requests** on pods for accurate node sizing
3. **Use multiple instance types** for better availability and cost optimization
4. **Monitor Karpenter metrics** in Grafana/CloudWatch
5. **Test disruption scenarios** before production deployment
6. **Use Spot instances** for non-critical workloads (70% spot recommended)
7. **Set expiration** to force regular node updates (30 days recommended)

## Integration with HPA

Karpenter works seamlessly with Horizontal Pod Autoscaler:

1. **HPA scales pods** based on CPU/memory metrics (3-50 replicas)
2. **Karpenter provisions nodes** to accommodate pending pods (<30s)
3. **Karpenter consolidates** when pods scale down (30s after)

## Security Considerations

- **IMDSv2 required**: Prevents SSRF attacks
- **Encrypted EBS volumes**: Data at rest encryption
- **Private subnets only**: Nodes not exposed to internet
- **Security group restrictions**: Least privilege network access
- **IAM roles**: Fine-grained permissions via IRSA

## Monitoring

Key metrics to monitor:

- `karpenter_nodes_created`: Rate of node provisioning
- `karpenter_nodes_terminated`: Rate of node termination
- `karpenter_pods_startup_duration`: Time to schedule pods
- `karpenter_nodeclaims_disrupted`: Disruption events
- `karpenter_nodepools_usage`: Resource utilization

## References

- [Karpenter Documentation](https://karpenter.sh/)
- [AWS Karpenter Best Practices](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [Karpenter vs Cluster Autoscaler](https://karpenter.sh/docs/concepts/comparison/)

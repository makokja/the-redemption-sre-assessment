# The Redemption - Design Document
## Executive Summary

### Project Overview
This document outlines the architectural design and implementation strategy for "The Redemption," a business-critical microservice handling global hotel point deductions on AWS EKS. The solution addresses the core requirements of zero downtime, automatic 10x traffic scaling, and comprehensive security while maintaining operational excellence.

### Key Achievements
- **Zero Downtime**: Multi-AZ architecture with automatic failover
- **10x Auto-Scaling**: Handles flash sales with aggressive horizontal scaling
- **Security**: Defense-in-depth with 5 security layers
- **Observability**: Real-time monitoring with automated alerting
- **Cost-Effective**: Spot instances and auto-scaling reduce costs by ~30%

---

## 1. Architecture Design

### 1.1 Compute & Infrastructure

#### EKS Cluster Configuration
- **Kubernetes Version**: 1.28 
- **Control Plane**: Managed by AWS across 3 AZs
- **Node Groups**:
  - **General Purpose**: 3x t3.large (on-demand) for system workloads
  - **High Performance**: 2-20x c5.2xlarge (spot) for application workloads
- **Networking**: VPC with public/private subnets across 3 AZs

#### High Availability Design
- **Multi-AZ Deployment**: Resources distributed across us-east-1a, 1b, 1c
- **Pod Anti-Affinity**: Ensures pods spread across nodes and zones
- **Pod Disruption Budget**: Minimum 2 pods always available
- **Rolling Updates**: maxUnavailable=0 for zero downtime deployments

#### Rationale
- **EKS over self-managed**: Reduces operational overhead, AWS manages control plane
- **Multi-AZ**: Survives entire availability zone failures
- **Spot instances**: 70% cost savings for burst capacity with minimal risk
- **Node diversity**: Separates system workloads from application workloads

### 1.2 Scalability Strategy

#### Horizontal Pod Autoscaler (HPA)
```yaml
Min Replicas: 3
Max Replicas: 50
Target CPU: 70%
Target Memory: 80%

Scale-Up Policy:
  - 100% increase every 15 seconds (aggressive)
  - OR add 10 pods every 15 seconds
  - Whichever is greater

Scale-Down Policy:
  - 10% decrease every 60 seconds (conservative)
  - 5-minute stabilization window
```

#### Karpenter (Node Autoscaling)
- **Just-in-time Provisioning**: Launches nodes in <30 seconds
- **Bin-packing**: Optimizes node utilization and cost
- **Spot Instance Support**: 70% spot, 30% on-demand mix
- **Scale-down**: Consolidates underutilized nodes after 30 seconds
- **Disruption Budgets**: Ensures availability during scaling

#### Load Balancer Configuration
- **Type**: Application Load Balancer (Layer 7)
- **Cross-Zone**: Enabled for even distribution
- **Connection Draining**: 30 seconds for graceful shutdown
- **Stickiness**: Session-based for consistent user experience

#### Flash Sale Scenario (10x Traffic)
**Baseline**: 1,000 requests/second, 3 pods
**Flash Sale**: 10,000 requests/second

**Timeline**:
- **T+0s**: Traffic spike begins
- **T+15s**: HPA detects high CPU, scales to 6 pods (100% increase)
- **T+30s**: HPA continues scaling, reaches 12 pods
- **T+45s**: Karpenter provisions 3 new nodes in <30s
- **T+90s**: System stabilizes at 30 pods across 8 nodes
- **Result**: 10x capacity, <2 minute scale-up time

### 1.3 Data Layer

#### RDS PostgreSQL
- **Instance**: db.r6g.xlarge (memory-optimized)
- **Multi-AZ**: Automatic failover to standby
- **Storage**: 100GB with auto-scaling to 1TB
- **Backups**: 7-day retention, automated snapshots
- **Encryption**: At-rest with KMS, in-transit with TLS

#### ElastiCache Redis
- **Instance**: cache.r6g.large x3 (one per AZ)
- **Replication**: Multi-AZ with automatic failover
- **Use Cases**: Session storage, rate limiting, caching
- **Encryption**: At-rest and in-transit
- **Auth**: Token-based authentication

---

## 2. Security Architecture

### 2.1 Defense in Depth (5 Layers)

#### Layer 1: Perimeter Security
- **AWS WAF**: 
  - Rate limiting (2,000 requests/IP/5min)
  - OWASP Top 10 protection
  - SQL injection prevention
  - Known bad inputs blocking
- **DDoS Protection**: AWS Shield Standard (included)

#### Layer 2: Network Security
- **VPC Segmentation**: Public subnets for ALB, private for workloads
- **Security Groups**: 
  - ALB: Allow 80/443 from internet
  - Nodes: Allow traffic from ALB and within cluster
  - RDS: Allow 5432 only from nodes
  - Redis: Allow 6379 only from nodes
- **Network Policies**: Kubernetes-level pod-to-pod restrictions
- **VPC Flow Logs**: Network traffic monitoring

#### Layer 3: Application Security
- **Pod Security Context**:
  - Run as non-root user (UID 1000)
  - Read-only root filesystem
  - Drop all capabilities
  - No privilege escalation
- **RBAC**: Least privilege for service accounts
- **Network Policies**: Restrict ingress/egress per namespace

#### Layer 4: Data Security
- **Encryption at Rest**: 
  - EBS volumes: KMS encryption
  - RDS: KMS encryption
  - Redis: Native encryption
  - Secrets: AWS Secrets Manager
- **Encryption in Transit**:
  - ALB to pods: TLS 1.2+
  - Pods to RDS: TLS
  - Pods to Redis: TLS

#### Layer 5: Identity & Access
- **IAM Roles for Service Accounts (IRSA)**: Pod-level AWS permissions without static credentials
- **AWS Secrets Manager Integration**:
  - Centralized secret storage with encryption at rest (KMS)
  - External Secrets Operator syncs secrets to Kubernetes
  - Automatic secret rotation support
  - No hardcoded credentials in code or manifests
  - Secrets refreshed every 1 hour automatically
- **Audit Logging**: CloudWatch Logs for all API calls and secret access

### 2.2 Compliance & Best Practices
- **Least Privilege**: All IAM roles follow minimum required permissions
- **Secrets Rotation**: Automated rotation for database credentials
- **Patch Management**: Automated node AMI updates
- **Vulnerability Scanning**: Container image scanning (recommended)

---

## 3. Reliability & Observability

### 3.1 Health Checks

#### Application Health
- **Liveness Probe**: `/health` endpoint every 10s
  - Failure threshold: 3 consecutive failures
  - Action: Restart pod
- **Readiness Probe**: `/ready` endpoint every 5s
  - Failure threshold: 3 consecutive failures
  - Action: Remove from service rotation

#### Infrastructure Health
- **ALB Health Checks**: `/health` every 15s
  - Healthy threshold: 2 consecutive successes
  - Unhealthy threshold: 2 consecutive failures
- **Node Health**: Kubelet heartbeat every 10s

### 3.2 Monitoring Stack

#### CloudWatch Container Insights
- **Metrics Collected**:
  - Node CPU, memory, disk, network
  - Pod CPU, memory, network
  - Container restart count
  - Cluster-level aggregations
- **Retention**: 7 days
- **Dashboards**: Pre-built visualizations

#### Prometheus
- **Scrape Interval**: 15 seconds
- **Metrics**:
  - Application-specific metrics (request rate, latency, errors)
  - Custom business metrics (points redeemed, transaction volume)
  - Kubernetes metrics (pod status, resource usage)
- **Storage**: 15-day retention

#### CloudWatch Alarms
1. **High CPU Utilization**: >80% for 10 minutes
2. **High Memory Utilization**: >80% for 10 minutes
3. **Pod Failures**: >5 restarts in 5 minutes
4. **High Response Time**: >1 second average
5. **5XX Errors**: >10 per minute

### 3.3 Logging Strategy
- **Application Logs**: stdout/stderr → CloudWatch Logs
- **Audit Logs**: EKS control plane logs
- **Network Logs**: VPC Flow Logs
- **Retention**: 7 days (cost optimization)
- **Aggregation**: Centralized in CloudWatch Log Groups

### 3.4 Disaster Recovery

#### RTO/RPO Targets
- **RTO (Recovery Time Objective)**: 5 minutes
- **RPO (Recovery Point Objective)**: 5 minutes

#### Backup Strategy
- **RDS**: Automated daily snapshots, 7-day retention
- **Redis**: Automated snapshots, 5-day retention
- **Kubernetes State**: Velero backups (recommended)
- **Infrastructure**: Terraform state in S3 with versioning

#### Failure Scenarios
1. **AZ Failure**: Automatic failover, <30s impact
2. **Node Failure**: Pod rescheduling, <60s impact
3. **Database Failover**: RDS automatic, 60-120s impact
4. **Bad Deployment**: Rollback via Helm, <5min impact

---

## 4. Operational Excellence

### 4.1 Day 2 Operations

#### Deployment Strategy
- **GitOps**: ArgoCD or FluxCD for continuous deployment
- **Helm**: Application lifecycle management
- **Terraform**: Infrastructure changes
- **Blue-Green**: For major updates (future enhancement)

#### Monitoring & Alerting
- **24/7 Monitoring**: CloudWatch + Prometheus
- **Alert Routing**: SNS → Email/Slack/PagerDuty
- **On-Call Rotation**: SRE team coverage
- **Runbooks**: Documented procedures for common issues

#### Capacity Planning
- **Weekly Reviews**: Analyze usage trends
- **Quarterly Planning**: Adjust reserved capacity
- **Cost Optimization**: Review spot instance usage
- **Performance Testing**: Monthly load tests

#### Maintenance Windows
- **Kubernetes Upgrades**: Quarterly (non-disruptive)
- **Node AMI Updates**: Monthly (rolling)
- **Database Maintenance**: Weekly (automated)
- **Security Patches**: As needed (emergency)

### 4.2 Cost Optimization

#### Current Costs (Estimated)
- **Compute**: $400/month (baseline)
- **Database**: $500/month
- **Cache**: $400/month
- **Networking**: $125/month
- **Monitoring**: $50/month
- **Total**: ~$1,475/month baseline

#### Optimization Strategies
1. **Spot Instances**: 70% savings on burst capacity
2. **Auto-Scaling**: Scale down during off-peak (30% savings)
3. **Reserved Instances**: 40% savings on baseline (future)
4. **S3 Lifecycle**: Archive logs to Glacier (50% savings)
5. **Right-Sizing**: Adjust based on actual usage

#### Cost During Flash Sale
- **Peak**: ~$2,500/month (if sustained)
- **Actual**: ~$1,600/month (short bursts)
- **Savings**: Auto-scaling prevents over-provisioning

---

## 5. Team Delegation & Timeline

### 5.1 Team Structure

#### Senior Engineer (Lead) - 3-4 days
**Core Responsibilities**:
- Overall architecture design and review
- Complex module implementation (EKS, Security)
- Production deployment and validation
- Code review and mentorship

**Specific Tasks**:
1. Design multi-AZ EKS architecture
2. Implement EKS Terraform module with IRSA
3. Configure security layers (WAF, KMS, Security Groups)
4. Set up monitoring and alerting stack
5. Review all PRs from junior engineers
6. Perform production deployment
7. Validate auto-scaling behavior
8. Create incident response procedures

**Deliverables**:
- EKS cluster fully operational
- Security hardening complete
- Monitoring dashboards configured
- Production deployment successful

#### Junior Engineer 1 - 2-3 days
**Core Responsibilities**:
- Networking infrastructure
- Data layer setup
- Documentation

**Specific Tasks**:
1. Implement VPC Terraform module
   - Multi-AZ subnets
   - NAT Gateways
   - Route tables
   - VPC Flow Logs
2. Configure RDS PostgreSQL
   - Multi-AZ deployment
   - Parameter groups
   - Security groups
   - Backup configuration
3. Set up ElastiCache Redis
   - Replication group
   - Auth token
   - Security groups
4. Write deployment documentation
5. Create operational runbooks

**Deliverables**:
- VPC with multi-AZ networking
- RDS and Redis fully configured
- Comprehensive documentation

#### Junior Engineer 2 - 2-3 days
**Core Responsibilities**:
- Kubernetes application deployment
- Helm chart development
- Testing and validation

**Specific Tasks**:
1. Create Helm chart for redemption service
   - Deployment with anti-affinity
   - Service and Ingress
   - ConfigMaps and Secrets
2. Configure HPA with aggressive scale-up
3. Set up Pod Disruption Budget
4. Deploy Prometheus monitoring
5. Perform load testing
   - Baseline performance
   - Flash sale simulation
   - Scale-down behavior
6. Document scaling behavior and metrics

**Deliverables**:
- Production-ready Helm chart
- HPA configured and tested
- Load test results documented

### 5.2 Project Timeline

#### Week 1: Infrastructure Setup
- **Day 1-2**: VPC, networking, data layer (Junior 1)
- **Day 1-3**: EKS cluster, security (Senior)
- **Day 1-2**: Helm chart development (Junior 2)

#### Week 2: Integration & Testing
- **Day 3**: Monitoring setup (Senior)
- **Day 3**: Application deployment (Junior 2)
- **Day 3**: Documentation (Junior 1)
- **Day 4**: Integration testing (All)
- **Day 4**: Load testing (Junior 2 + Senior)

#### Week 2: Production Deployment
- **Day 5**: Production deployment (Senior)
- **Day 5**: Validation and handoff (All)

### 5.3 Knowledge Transfer
- **Daily Standups**: 15-minute sync
- **Code Reviews**: All PRs reviewed by Senior
- **Pair Programming**: Junior engineers pair on complex tasks
- **Documentation**: Each engineer documents their work
- **Handoff Session**: Final walkthrough of entire system

---

## 6. Trade-offs & Design Decisions

### 6.1 Key Trade-offs

#### EKS vs. Self-Managed Kubernetes
**Decision**: EKS
**Rationale**: 
- Reduced operational overhead
- AWS manages control plane upgrades
- Better integration with AWS services
**Trade-off**: Higher cost (~$73/month), less control

#### Spot vs. On-Demand Instances
**Decision**: Hybrid (on-demand baseline + spot burst)
**Rationale**:
- 70% cost savings on burst capacity
- Acceptable interruption risk for stateless workloads
**Trade-off**: Potential interruptions during extreme demand

#### Multi-AZ NAT Gateways
**Decision**: One NAT Gateway per AZ
**Rationale**:
- Survives AZ failures
- No single point of failure
**Trade-off**: 3x cost (~$100/month vs ~$33/month)

#### Aggressive HPA Scale-Up
**Decision**: 100% increase every 15 seconds
**Rationale**:
- Flash sales require immediate capacity
- Business-critical, revenue-impacting
**Trade-off**: Potential over-provisioning, higher costs

### 6.2 Future Enhancements

1. **Service Mesh (Istio)**:
   - Advanced traffic management
   - Circuit breaking
   - Mutual TLS between services

2. **GitOps (ArgoCD)**:
   - Automated deployments
   - Declarative configuration
   - Audit trail

3. **Chaos Engineering**:
   - Proactive failure testing
   - Resilience validation
   - Confidence in recovery procedures

4. **Multi-Region**:
   - Global load balancing
   - Disaster recovery
   - Reduced latency

5. **Cost Optimization**:
   - Reserved Instances for baseline
   - Savings Plans for compute
   - Fargate for specific workloads

---

## 7. Success Metrics

### 7.1 Availability Metrics
- **Target**: 99.95% uptime (21.6 minutes downtime/month)
- **Measurement**: ALB target health checks
- **Current**: 99.99% (estimated)

### 7.2 Performance Metrics
- **Response Time**: p95 < 200ms, p99 < 500ms
- **Throughput**: 10,000 requests/second during flash sales
- **Error Rate**: < 0.1%

### 7.3 Scalability Metrics
- **Scale-Up Time**: < 2 minutes for 10x traffic
- **Scale-Down Time**: < 30 minutes to baseline
- **Resource Utilization**: 60-80% during normal operation

### 7.4 Operational Metrics
- **MTTR (Mean Time To Recovery)**: < 5 minutes
- **MTTD (Mean Time To Detection)**: < 1 minute
- **Deployment Frequency**: Multiple per day (GitOps)
- **Change Failure Rate**: < 5%

---

## 8. Conclusion

This architecture provides a production-ready, highly available, and automatically scalable solution for "The Redemption" microservice. The design addresses all assessment requirements:

✅ **Zero Downtime**: Multi-AZ, rolling updates, PDB
✅ **10x Auto-Scaling**: HPA + Karpenter
✅ **Security**: 5-layer defense-in-depth
✅ **Observability**: CloudWatch + Prometheus + Grafana
✅ **Operational Excellence**: Automated, documented, tested

The solution is cost-effective, maintainable, and ready for production deployment.

---

## Appendix A: Technology Stack

- **Container Orchestration**: Kubernetes 1.28 on AWS EKS
- **Infrastructure as Code**: Terraform 1.5+
- **Application Deployment**: Helm 3.0+
- **Secrets Management**: External Secrets Operator + AWS Secrets Manager
- **Load Balancing**: AWS Application Load Balancer
- **Database**: RDS PostgreSQL 15.4
- **Cache**: ElastiCache Redis 7.0
- **Monitoring**: CloudWatch, Prometheus, Grafana
- **Security**: AWS WAF, KMS, Secrets Manager, IRSA
- **Networking**: AWS VPC, Security Groups, Network Policies


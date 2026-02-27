terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Remote state configuration
  backend "s3" {
    bucket = "the-redemption-terraform-state"
    key = "production/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  # Apply default tags to all resources
  default_tags {
    tags = {
      Project = "the-redemption"
      Environment = var.environment
      ManagedBy = "terraform"
      CostCenter = "revenue-critical"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# VPC setup with multi-AZ configuration
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "${var.project_name}-vpc"
  vpc_cidr = var.vpc_cidr
  availability_zones = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs = var.public_subnet_cidrs
  
  # NAT Gateway configuration - using multiple NATs for high availability
  enable_nat_gateway = true
  single_nat_gateway = false
  
  enable_dns_hostnames = true
  enable_dns_support = true
  
  tags = {
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# EKS cluster configuration
module "eks" {
  source = "./modules/eks"

  cluster_name = "${var.project_name}-cluster"
  cluster_version = var.eks_cluster_version
  
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  # Configure node groups - general purpose and high performance
  node_groups = {
    general = {
      desired_capacity = 3
      min_capacity     = 3
      max_capacity     = 10
      instance_types   = ["t3.large"]
      capacity_type    = "ON_DEMAND"
      
      labels = {
        role = "general"
      }
      
      taints = []
    }
    
    high_performance = {
      desired_capacity = 2
      min_capacity = 2
      max_capacity = 20
      instance_types = ["c5.2xlarge"]
      capacity_type = "SPOT" # using spot instances for cost savings
      
      labels = {
        role = "high-performance"
        workload = "redemption"
      }
      
      taints = [{
        key = "workload"
        value = "redemption"
        effect = "NoSchedule"
      }]
    }
  }
  
  enable_irsa = true
  
  # Install essential cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }
  
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  
  tags = {
    Environment = var.environment
  }
}

# Security configuration
module "security" {
  source = "./modules/security"

  vpc_id = module.vpc.vpc_id
  cluster_name = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id = module.eks.node_security_group_id
  
  enable_waf = true
  enable_secrets_encryption = true
}

# Monitoring Module
module "monitoring" {
  source = "./modules/monitoring"

  cluster_name           = module.eks.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  
  # CloudWatch Container Insights
  enable_container_insights = true
  
  # Prometheus & Grafana
  enable_prometheus = true
  enable_grafana    = true
  
  # Alert configuration
  alert_email = var.alert_email
  
  tags = {
    Environment = var.environment
  }
}

# ALB for ingress traffic
resource "aws_lb" "redemption" {
  name = "${var.project_name}-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [module.security.alb_security_group_id]
  subnets = module.vpc.public_subnet_ids

  enable_deletion_protection = true
  enable_http2 = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# WAF Web ACL Association
resource "aws_wafv2_web_acl_association" "redemption" {
  count = module.security.waf_web_acl_arn != "" ? 1 : 0
  
  resource_arn = aws_lb.redemption.arn
  web_acl_arn  = module.security.waf_web_acl_arn
}

# Database subnet group
resource "aws_db_subnet_group" "redemption" {
  name = "${var.project_name}-db-subnet"
  subnet_ids = module.vpc.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet"
  }
}

# PostgreSQL RDS instance with multi-AZ
resource "aws_db_instance" "redemption" {
  identifier = "${var.project_name}-db"
  engine = "postgres"
  engine_version = "15.4"
  instance_class = "db.r6g.xlarge"
  
  allocated_storage = 100
  max_allocated_storage = 1000
  storage_encrypted = true
  
  db_name = "redemption"
  username = "redemption_admin"
  password = random_password.db_password.result
  
  multi_az = true
  db_subnet_group_name = aws_db_subnet_group.redemption.name
  vpc_security_group_ids = [module.security.rds_security_group_id]
  
  # Backup configuration
  backup_retention_period = 7
  backup_window = "03:00-04:00"
  maintenance_window = "mon:04:00-mon:05:00"
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = {
    Name = "${var.project_name}-db"
  }
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.project_name}/db-password"
  
  tags = {
    Name = "${var.project_name}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = aws_db_instance.redemption.username
    password = random_password.db_password.result
    host     = aws_db_instance.redemption.address
    port     = aws_db_instance.redemption.port
    dbname   = aws_db_instance.redemption.db_name
  })
}

# Redis cache subnet group
resource "aws_elasticache_subnet_group" "redemption" {
  name = "${var.project_name}-cache-subnet"
  subnet_ids = module.vpc.private_subnet_ids
}

# ElastiCache Redis cluster
resource "aws_elasticache_replication_group" "redemption" {
  replication_group_id = "${var.project_name}-redis"
  replication_group_description = "Redis cluster for The Redemption service"
  
  engine = "redis"
  engine_version = "7.0"
  node_type = "cache.r6g.large"
  num_cache_clusters = 3
  
  parameter_group_name = "default.redis7"
  port = 6379
  
  subnet_group_name = aws_elasticache_subnet_group.redemption.name
  security_group_ids = [module.security.redis_security_group_id]
  
  # Enable failover and multi-AZ
  automatic_failover_enabled = true
  multi_az_enabled = true
  
  # Encryption settings
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled = true
  auth_token = random_password.redis_auth_token.result
  
  snapshot_retention_limit = 5
  snapshot_window = "03:00-05:00"
  
  tags = {
    Name = "${var.project_name}-redis"
  }
}

resource "random_password" "redis_auth_token" {
  length = 32
  special = false
}

resource "aws_secretsmanager_secret" "redis_auth_token" {
  name = "${var.project_name}/redis-auth-token"
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth_token.result
    endpoint   = aws_elasticache_replication_group.redemption.configuration_endpoint_address
    port       = aws_elasticache_replication_group.redemption.port
  })
}

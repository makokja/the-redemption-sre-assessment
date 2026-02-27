output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = false
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.redemption.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.redemption.zone_id
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.redemption.endpoint
  sensitive   = true
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.redemption.db_name
}

output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_replication_group.redemption.configuration_endpoint_address
  sensitive   = true
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_replication_group.redemption.port
}

output "db_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "redis_secret_arn" {
  description = "ARN of the Redis auth token secret"
  value       = aws_secretsmanager_secret.redis_auth_token.arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

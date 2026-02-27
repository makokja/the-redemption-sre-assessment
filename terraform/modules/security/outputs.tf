output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "redis_security_group_id" {
  description = "Security group ID for Redis"
  value       = aws_security_group.redis.id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = try(aws_wafv2_web_acl.main[0].arn, "")
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key for secrets encryption"
  value       = try(aws_kms_key.secrets[0].arn, "")
}

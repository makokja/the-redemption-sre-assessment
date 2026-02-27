variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  type        = string
}

variable "node_security_group_id" {
  description = "EKS node security group ID"
  type        = string
}

variable "enable_waf" {
  description = "Enable WAF for ALB"
  type        = bool
  default     = true
}

variable "enable_secrets_encryption" {
  description = "Enable KMS encryption for secrets"
  type        = bool
  default     = true
}

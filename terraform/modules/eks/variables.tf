variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "Map of node group configurations"
  type = map(object({
    desired_capacity = number
    min_capacity     = number
    max_capacity     = number
    instance_types   = list(string)
    capacity_type    = string
    labels           = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {}
}

variable "cluster_addons" {
  description = "Map of cluster addon configurations"
  type        = map(any)
  default     = {}
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

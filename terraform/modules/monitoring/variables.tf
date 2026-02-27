variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster"
  type        = string
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

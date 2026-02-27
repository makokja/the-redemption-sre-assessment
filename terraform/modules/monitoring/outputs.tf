output "container_insights_role_arn" {
  description = "IAM role ARN for Container Insights"
  value       = try(aws_iam_role.container_insights[0].arn, "")
}

output "prometheus_role_arn" {
  description = "IAM role ARN for Prometheus"
  value       = try(aws_iam_role.prometheus[0].arn, "")
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

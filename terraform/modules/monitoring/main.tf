# Monitoring Module - Comprehensive Observability Stack

# CloudWatch Container Insights
resource "aws_iam_role" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  name = "${var.cluster_name}-container-insights-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.container_insights[0].name
}

data "aws_caller_identity" "current" {}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${var.cluster_name}/application"
  retention_in_days = 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "dataplane" {
  name              = "/aws/eks/${var.cluster_name}/dataplane"
  retention_in_days = 7

  tags = var.tags
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.cluster_name}-alerts"

  tags = var.tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Alarms

# High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.cluster_name}-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors EKS node CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = var.tags
}

# High Memory Utilization
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${var.cluster_name}-high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors EKS node memory utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = var.tags
}

# Pod Failures
resource "aws_cloudwatch_metric_alarm" "pod_failures" {
  alarm_name          = "${var.cluster_name}-pod-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This metric monitors pod restart count"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = var.tags
}

# Application Response Time
resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "${var.cluster_name}-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1.0
  alarm_description   = "This metric monitors ALB target response time"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# 5XX Errors
resource "aws_cloudwatch_metric_alarm" "high_5xx_errors" {
  alarm_name          = "${var.cluster_name}-high-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors 5XX errors from targets"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.cluster_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", { stat = "Average" }],
            [".", "node_memory_utilization", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Node Resource Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            [".", "RequestCount", { stat = "Sum" }]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Application Performance"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", { stat = "Sum" }],
            [".", "HTTPCode_Target_4XX_Count", { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum" }]
          ]
          period = 60
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "HTTP Response Codes"
        }
      }
    ]
  })
}

data "aws_region" "current" {}

# IAM Role for Prometheus
resource "aws_iam_role" "prometheus" {
  count = var.enable_prometheus ? 1 : 0

  name = "${var.cluster_name}-prometheus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:monitoring:prometheus"
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "prometheus" {
  count = var.enable_prometheus ? 1 : 0

  name = "${var.cluster_name}-prometheus-policy"
  role = aws_iam_role.prometheus[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

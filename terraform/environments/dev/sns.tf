
resource "aws_sns_topic" "monitoring_alerts" {
  name = "project2-monitoring-alerts"

  tags = {
    Project     = "devops-observability-project"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  sensitive   = true
}

output "monitoring_sns_topic_arn" {
  description = "SNS topic ARN for Project 2 alerts"
  value       = aws_sns_topic.monitoring_alerts.arn
}


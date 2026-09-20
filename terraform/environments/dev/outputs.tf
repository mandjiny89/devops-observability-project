output "monitoring_instance_id" {
  value = module.monitoring_host.instance_id
}

output "monitoring_public_ip" {
  value = module.monitoring_host.public_ip
}

output "grafana_url" {
  value = "http://${module.monitoring_host.public_ip}:3000"
}

output "prometheus_ssm_command" {
  value = "aws ssm start-session --target ${module.monitoring_host.instance_id} --region ${var.aws_region} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"9090\"],\"localPortNumber\":[\"9090\"]}'"
}

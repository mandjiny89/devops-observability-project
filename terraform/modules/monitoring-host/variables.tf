variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "project1_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "project1_app_sg_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "grafana_allowed_cidr" {
  type = string
}

variable "webhook_secret_arn" {
  description = "ARN of the Alertmanager webhook secret"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "IPv4 CIDR allowed to SSH into the monitoring EC2"
  type        = string
}

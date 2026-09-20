variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "project_name" {
  type    = string
  default = "devops-observability-project"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project1_name" {
  type    = string
  default = "devops-cicd-project"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "grafana_allowed_cidr" {
  description = "CIDR allowed to access Grafana during the dev lab."
  type        = string
  default     = "0.0.0.0/0"
}

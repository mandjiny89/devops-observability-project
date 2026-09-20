data "aws_vpc" "project1" {
  filter {
    name   = "tag:Name"
    values = ["${var.project1_name}-${var.environment}-vpc"]
  }
}

data "aws_subnets" "project1_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.project1.id]
  }

  filter {
    name   = "tag:Tier"
    values = ["public"]
  }
}

data "aws_security_group" "project1_app" {
  filter {
    name   = "group-name"
    values = ["${var.project1_name}-${var.environment}-app-sg"]
  }

  vpc_id = data.aws_vpc.project1.id
}

module "monitoring_host" {
  source = "../../modules/monitoring-host"

  project_name         = var.project_name
  environment          = var.environment
  project1_name        = var.project1_name
  aws_region           = var.aws_region
  vpc_id               = data.aws_vpc.project1.id
  subnet_id            = sort(data.aws_subnets.project1_public.ids)[0]
  project1_app_sg_id   = data.aws_security_group.project1_app.id
  instance_type        = var.instance_type
  grafana_allowed_cidr = var.grafana_allowed_cidr
}

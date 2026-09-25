data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Project 2 monitoring host"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "grafana" {
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = var.grafana_allowed_cidr
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
  description       = "Grafana UI"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "project1_fastapi_metrics" {
  security_group_id            = var.project1_app_sg_id
  referenced_security_group_id = aws_security_group.monitoring.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "Prometheus FastAPI scrape from Project 2"
}

resource "aws_vpc_security_group_ingress_rule" "project1_node_exporter" {
  security_group_id            = var.project1_app_sg_id
  referenced_security_group_id = aws_security_group.monitoring.id
  from_port                    = 9100
  to_port                      = 9100
  ip_protocol                  = "tcp"
  description                  = "Prometheus Node Exporter scrape from Project 2"
}

resource "aws_iam_role" "monitoring" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_discovery" {
  name = "${var.project_name}-${var.environment}-ec2-discovery"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-${var.environment}-profile"
  role = aws_iam_role.monitoring.name
}

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.monitoring.name
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf install -y docker
    systemctl enable --now docker

    mkdir -p /opt/observability/prometheus/rules
    mkdir -p /opt/observability/prometheus-data
    mkdir -p /opt/observability/grafana-data
    mkdir -p /opt/observability/grafana-provisioning/datasources
    mkdir -p /opt/observability/grafana-provisioning/dashboards
    mkdir -p /opt/observability/grafana-dashboards
    
    echo '${base64encode(file("${path.module}/../../../grafana/dashboards/project1-infrastructure.json"))}' \
      | base64 -d \
      > /opt/observability/grafana-dashboards/project1-infrastructure.json
 
    chown -R 65534:65534 /opt/observability/prometheus-data
    chown -R 472:472 /opt/observability/grafana-data

    cat > /opt/observability/grafana-provisioning/dashboards/dashboards.yml <<'DASHBOARDS'
    apiVersion: 1

    providers:
      - name: Project 1
        orgId: 1
        folder: Project 1
        type: file
        disableDeletion: false
        updateIntervalSeconds: 30
        allowUiUpdates: true
        options:
          path: /var/lib/grafana/dashboards
    DASHBOARDS

    cat > /opt/observability/prometheus/prometheus.yml <<'PROMETHEUS'
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - /etc/prometheus/rules/*.yml

    scrape_configs:
      - job_name: project1-fastapi
        metrics_path: /metrics
        ec2_sd_configs:
          - region: ${var.aws_region}
            port: 80
            filters:
              - name: tag:Project
                values:
                  - ${var.project1_name}
              - name: tag:Environment
                values:
                  - ${var.environment}
              - name: tag:Role
                values:
                  - app
              - name: instance-state-name
                values:
                  - running
        relabel_configs:
          - source_labels: [__meta_ec2_private_ip]
            target_label: __address__
            replacement: $${1}:80
          - source_labels: [__meta_ec2_instance_id]
            target_label: instance_id
          - source_labels: [__meta_ec2_availability_zone]
            target_label: availability_zone

      - job_name: project1-node
        ec2_sd_configs:
          - region: ${var.aws_region}
            port: 9100
            filters:
              - name: tag:Project
                values:
                  - ${var.project1_name}
              - name: tag:Environment
                values:
                  - ${var.environment}
              - name: tag:Role
                values:
                  - app
              - name: instance-state-name
                values:
                  - running
        relabel_configs:
          - source_labels: [__meta_ec2_private_ip]
            target_label: __address__
            replacement: $${1}:9100
          - source_labels: [__meta_ec2_instance_id]
            target_label: instance_id
    PROMETHEUS

    cat > /opt/observability/prometheus/rules/application.yml <<'RULES'
    groups:
      - name: project1-availability
        rules:
          - alert: Project1FastAPIDown
            expr: up{job="project1-fastapi"} == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Project 1 FastAPI target is down"

          - alert: Project1NodeExporterDown
            expr: up{job="project1-node"} == 0
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "Project 1 Node Exporter target is down"
    RULES

    cat > /opt/observability/grafana-provisioning/datasources/prometheus.yml <<'GRAFANA'
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus
        type: prometheus
        access: proxy
        url: http://127.0.0.1:9090
        isDefault: true
        editable: false
    GRAFANA

    chown -R 472:472 /opt/observability/grafana-data

    docker pull prom/prometheus:v3.5.0
    docker pull grafana/grafana:12.1.1

    docker rm -f prometheus || true
    docker run -d \
      --name prometheus \
      --restart unless-stopped \
      --network host \
      -v /opt/observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
      -v /opt/observability/prometheus/rules:/etc/prometheus/rules:ro \
      -v /opt/observability/prometheus-data:/prometheus \
      prom/prometheus:v3.5.0 \
      --config.file=/etc/prometheus/prometheus.yml \
      --storage.tsdb.path=/prometheus

    docker rm -f grafana || true
    docker run -d \
      --name grafana \
      --restart unless-stopped \
      --network host \
      -v /opt/observability/grafana-data:/var/lib/grafana \
      -v /opt/observability/grafana-provisioning:/etc/grafana/provisioning:ro \
      -v /opt/observability/grafana-dashboards:/var/lib/grafana/dashboards:ro \
      grafana/grafana:12.1.1
  EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-monitoring"
    Role = "monitoring"
  }
}

# DevOps Observability Project

Project 2 provides Prometheus/Grafana observability for the AWS application infrastructure created by Project 1 (`devops-cicd-project`).

## Relationship with Project 1

Project 1 owns the application infrastructure. Project 2 owns the observability infrastructure.

```text
Project 1 ASG application instances
  Project=devops-cicd-project
  Environment=dev
  Role=app
             |
             | AWS EC2 service discovery
             v
Project 2 Prometheus -> Grafana
```

Project 2 uses dynamic AWS discovery. Project 1 EC2 instance IDs and IP addresses are not hard-coded.

## Repository identity

```text
GitHub owner:      mandjiny89
Owner ID:          35368639
Repository:        devops-observability-project
Repository ID:     1377996457
Branch:            main
AWS account:       861019856428
AWS region:        eu-west-2
```

Retrieve the GitHub repository and owner IDs with:

```bash
curl -s https://api.github.com/repos/mandjiny89/devops-observability-project | grep '"id"'
```

OIDC subject:

```text
repo:mandjiny89@35368639/devops-observability-project@1377996457:ref:refs/heads/main
```

## GitHub OIDC

Existing AWS OIDC provider:

```text
arn:aws:iam::861019856428:oidc-provider/token.actions.githubusercontent.com
```

Project 2 role:

```text
arn:aws:iam::861019856428:role/devops-observability-github-actions-role
```

Trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::861019856428:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:mandjiny89@35368639/devops-observability-project@1377996457:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

No long-lived AWS access keys are required.

## Terraform backend

The `Observability CI/CD` workflow offers:

```text
bootstrap-backend
plan
deploy
destroy
```

Run `bootstrap-backend` first. It creates or verifies:

```text
devops-observability-project-tfstate-dev-861019856428-eu-west-2
```

with S3 versioning, AES-256 encryption, Block Public Access and BucketOwnerEnforced ownership.

The backend uses native S3 locking (`use_lockfile = true`). No DynamoDB lock table is required.

The backend bucket is not managed by the main Terraform configuration, so `destroy` does not remove the state bucket.

## Stage 1 infrastructure

Stage 1:

- Finds the existing Project 1 VPC.
- Finds a Project 1 public subnet.
- Finds the Project 1 application security group.
- Creates one Amazon Linux 2023 monitoring EC2 instance.
- Creates a dedicated Project 2 monitoring security group.
- Creates an EC2 IAM role for Prometheus AWS service discovery and SSM.
- Runs Prometheus and Grafana in Docker.
- Allows the monitoring SG to reach Project 1 app nodes on TCP/80 and TCP/9100.
- Prometheus discovers Project 1 instances from their AWS tags.
- FastAPI `/metrics` is scraped on port 80.
- Port 9100 is prepared for Node Exporter in Stage 2.

Prometheus port 9090 is deliberately not exposed publicly. SSM port forwarding can be used when direct Prometheus UI access is required.

Grafana is exposed on port 3000 for this dev lab. Tighten `grafana_allowed_cidr` later if required.

## First deployment

```text
1. Push Stage 1 to main.
2. Actions -> Observability CI/CD -> bootstrap-backend.
3. Run plan.
4. Review the plan.
5. Run deploy.
6. Verify Grafana.
7. Verify Prometheus FastAPI targets.
```

## Stage 2

Stage 2 will install Node Exporter on Project 1 ASG application instances and add CPU, memory, disk and network dashboards/rules.

Later stages will add Alertmanager, HTTP/5xx alerting, provisioned Grafana dashboards and the optional Project 1 -> Project 2 workflow trigger.

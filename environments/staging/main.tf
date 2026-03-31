###############################################################################
# Staging Environment - Main Configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-community-tfstate"
    key            = "staging/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    kms_key_id     = "alias/my-community-tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# Stack (공통 인프라: IAM + VPC + S3 + Route53 + ACM + SES + ECR + RDS + CloudTrail)
# =============================================================================
module "stack" {
  source = "../../modules/stack"

  project     = var.project
  environment = var.environment
  tags        = local.common_tags

  # IAM
  admin_username       = var.admin_username
  create_deployer_role = var.create_deployer_role

  # VPC
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway

  # S3
  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days
  create_uploads_bucket         = true
  uploads_cors_origins          = ["https://staging.my-community.shop"]

  # Route53 + ACM
  domain_name                   = var.domain_name
  api_domain_name               = var.api_domain_name
  acm_subject_alternative_names = ["staging.${var.domain_name}", "ws-staging.${var.domain_name}"]

  # ECR
  ecr_image_retention_count = var.ecr_image_retention_count
  ecr_additional_repositories = [
    "${var.project}-${var.environment}-backend-k8s",
    "${var.project}-${var.environment}-frontend-k8s",
  ]

  # RDS
  rds_engine_version        = var.rds_engine_version
  rds_instance_class        = var.rds_instance_class
  rds_allocated_storage     = var.rds_allocated_storage
  rds_max_allocated_storage = var.rds_max_allocated_storage
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  rds_multi_az              = var.rds_multi_az
  rds_backup_retention_days = var.rds_backup_retention_days
  rds_deletion_protection   = var.rds_deletion_protection
}

# =============================================================================
# K8s Cluster (kubeadm on EC2) — staging 전용
# =============================================================================
module "k8s_ec2" {
  source = "../../modules/k8s_ec2"
  count  = var.create_k8s_cluster ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id = module.stack.vpc_id
  # c7i-flex.large는 ap-northeast-2a 미지원 → 2b 서브넷만 전달
  public_subnet_ids = [module.stack.public_subnet_ids[1]]

  master_count    = 1
  worker_count    = 2
  haproxy_enabled = false

  ssh_key_name      = var.k8s_ssh_key_name
  allowed_ssh_cidrs = var.k8s_allowed_ssh_cidrs

  enable_s3_uploads     = true
  s3_uploads_bucket_arn = module.stack.uploads_bucket_arn

  tags = local.common_tags
}

# K8s → RDS 3306 접근 허용
resource "aws_security_group_rule" "rds_from_k8s" {
  count = var.create_k8s_cluster ? 1 : 0

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.stack.rds_security_group_id
  source_security_group_id = module.k8s_ec2[0].k8s_internal_sg_id
  description              = "K8s nodes to RDS MySQL"
}

# K8s DNS Records (HAProxy/Worker IP → 도메인)
resource "aws_route53_record" "k8s" {
  for_each = var.create_k8s_cluster ? toset([
    "staging",
    "api-staging",
    "ws-staging",
    "grafana-staging",
    "argocd-staging",
  ]) : toset([])

  zone_id = module.stack.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = module.k8s_ec2[0].worker_public_ips
}

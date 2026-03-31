###############################################################################
# Prod Environment - Main Configuration
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
    key            = "prod/terraform.tfstate"
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
  uploads_cors_origins          = ["https://my-community.shop"]

  # Route53 + ACM
  domain_name                   = var.domain_name
  api_domain_name               = var.api_domain_name
  acm_subject_alternative_names = [var.domain_name, "ws.${var.domain_name}"]

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
# EKS Cluster (Managed Node Group) — prod 전용
# =============================================================================
module "eks" {
  source = "../../modules/eks"
  count  = var.create_eks_cluster ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id             = module.stack.vpc_id
  private_subnet_ids = module.stack.private_subnet_ids

  cluster_version     = var.eks_cluster_version
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size

  enable_s3_uploads     = true
  s3_uploads_bucket_arn = module.stack.uploads_bucket_arn

  tags = local.common_tags
}

# EKS Node → RDS 3306 접근 허용
resource "aws_security_group_rule" "rds_from_eks" {
  count = var.create_eks_cluster ? 1 : 0

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.stack.rds_security_group_id
  source_security_group_id = module.eks[0].cluster_security_group_id
  description              = "EKS nodes to RDS MySQL"
}

# =============================================================================
# Secrets Manager (External Secrets Operator 연동용)
# =============================================================================
resource "aws_secretsmanager_secret" "community" {
  count = var.create_eks_cluster ? 1 : 0

  name        = "${var.project}-${var.environment}-community-secrets"
  description = "Community app secrets (ESO synced to K8s)"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "community" {
  count = var.create_eks_cluster ? 1 : 0

  secret_id = aws_secretsmanager_secret.community[0].id
  secret_string = jsonencode({
    DB_PASSWORD          = var.db_password
    SECRET_KEY           = ""
    GITHUB_CLIENT_ID     = ""
    GITHUB_CLIENT_SECRET = ""
    INTERNAL_API_KEY     = ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

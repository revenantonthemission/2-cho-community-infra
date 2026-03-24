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
# Module 0: IAM (루트 계정 대신 사용할 사용자/그룹/정책)
# =============================================================================
module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment

  admin_username       = var.admin_username
  create_deployer_role = var.create_deployer_role

  tags = local.common_tags
}

# =============================================================================
# Module 1: VPC
# =============================================================================
module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count

  single_nat_gateway = var.single_nat_gateway

  tags = local.common_tags
}

# =============================================================================
# Module 2: S3 (uploads + CloudTrail logs)
# =============================================================================
module "s3" {
  source = "../../modules/s3"

  project     = var.project
  environment = var.environment

  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

  # 업로드 S3 버킷 (K8s 환경에서 사용)
  create_uploads_bucket = true
  uploads_cors_origins  = ["https://my-community.shop"]

  tags = local.common_tags
}

# =============================================================================
# Module 3: Route 53 + ACM
# =============================================================================
module "route53" {
  source = "../../modules/route53"

  domain_name = var.domain_name
}

module "acm" {
  source = "../../modules/acm"

  project     = var.project
  environment = var.environment

  domain_name               = var.api_domain_name
  subject_alternative_names = [var.domain_name, "ws.${var.domain_name}"]
  zone_id                   = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 3.5: SES (이메일 발송)
# =============================================================================
module "ses" {
  source = "../../modules/ses"

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name
  zone_id     = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 4: ECR
# =============================================================================
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  image_retention_count = var.ecr_image_retention_count

  additional_repositories = [
    "${var.project}-${var.environment}-backend-k8s",
    "${var.project}-${var.environment}-frontend-k8s",
  ]

  tags = local.common_tags
}

# =============================================================================
# Module 5: RDS
# =============================================================================
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.vpc.private_subnet_ids
  rds_security_group_id = module.vpc.rds_security_group_id

  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention_days
  deletion_protection   = var.rds_deletion_protection

  tags = local.common_tags
}

# =============================================================================
# Module 11: CloudTrail
# =============================================================================
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  project     = var.project
  environment = var.environment

  cloudtrail_s3_bucket_id = module.s3.cloudtrail_logs_bucket_id
  log_retention_days      = var.cloudtrail_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# EKS Cluster (Managed Node Group)
# =============================================================================
module "eks" {
  source = "../../modules/eks"
  count  = var.create_eks_cluster ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_version     = var.eks_cluster_version
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size

  enable_s3_uploads     = true
  s3_uploads_bucket_arn = module.s3.uploads_bucket_arn

  tags = local.common_tags
}

# EKS Node → RDS 3306 접근 허용
resource "aws_security_group_rule" "rds_from_eks" {
  count = var.create_eks_cluster ? 1 : 0

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.vpc.rds_security_group_id
  source_security_group_id = module.eks[0].cluster_security_group_id
  description              = "EKS nodes to RDS MySQL"
}

# =============================================================================
# Secrets Manager (External Secrets Operator 연동용)
# K8s community-secrets의 값을 Secrets Manager에서 관리
# =============================================================================
resource "aws_secretsmanager_secret" "community" {
  count = var.create_eks_cluster ? 1 : 0

  name        = "${var.project}-${var.environment}-community-secrets"
  description = "Community app secrets (ESO synced to K8s)"

  tags = local.common_tags
}

# 초기 값은 빈 JSON — 실제 값은 AWS 콘솔 또는 CLI로 설정
# ESO가 이 secret을 읽어 K8s Secret으로 동기화
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

  # 초기 생성 후 AWS 콘솔/CLI에서 값을 업데이트하므로 이후 변경 무시
  lifecycle {
    ignore_changes = [secret_string]
  }
}

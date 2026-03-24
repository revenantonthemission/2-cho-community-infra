###############################################################################
# Dev Environment - Main Configuration
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
    key            = "dev/terraform.tfstate"
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
  source             = "../../modules/vpc"
  project            = var.project
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
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
# K8s Cluster (kubeadm on EC2)
# =============================================================================
module "k8s_ec2" {
  source = "../../modules/k8s_ec2"
  count  = var.create_k8s_cluster ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id = module.vpc.vpc_id
  # c7i-flex.large는 ap-northeast-2a 미지원 → 2b 서브넷만 전달
  public_subnet_ids = [module.vpc.public_subnet_ids[1]]

  ssh_key_name      = var.k8s_ssh_key_name
  allowed_ssh_cidrs = var.k8s_allowed_ssh_cidrs

  enable_s3_uploads     = true
  s3_uploads_bucket_arn = module.s3.uploads_bucket_arn

  tags = local.common_tags
}

# K8s → RDS 접근 허용 (접착 리소스: K8s 모듈 ↔ VPC 모듈 순환 참조 방지)
resource "aws_vpc_security_group_ingress_rule" "rds_from_k8s" {
  count = var.create_k8s_cluster ? 1 : 0

  security_group_id            = module.vpc.rds_security_group_id
  description                  = "MySQL from K8s nodes"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = module.k8s_ec2[0].k8s_internal_sg_id
}

# K8s DNS Records (Worker EIP → 도메인)
resource "aws_route53_record" "k8s" {
  for_each = var.create_k8s_cluster ? toset([
    # 메인 도메인
    "",
    "api",
    "ws",
    # K8s 서브도메인 (기존 유지)
    "api.k8s",
    "k8s",
    "ws.k8s",
    "grafana.k8s",
    # ArgoCD UI
    "argocd",
  ]) : toset([])

  zone_id = module.route53.zone_id
  name    = each.key == "" ? var.domain_name : "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = module.k8s_ec2[0].worker_public_ips
}

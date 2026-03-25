###############################################################################
# Stack Module - 9개 공통 모듈 조합
# 환경 간 공유되는 기본 인프라를 캡슐화
###############################################################################

# =============================================================================
# IAM
# =============================================================================
module "iam" {
  source = "../iam"

  project     = var.project
  environment = var.environment

  admin_username       = var.admin_username
  create_deployer_role = var.create_deployer_role

  tags = var.tags
}

# =============================================================================
# VPC
# =============================================================================
module "vpc" {
  source = "../vpc"

  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count

  single_nat_gateway = var.single_nat_gateway

  tags = var.tags
}

# =============================================================================
# S3 (uploads + CloudTrail logs)
# =============================================================================
module "s3" {
  source = "../s3"

  project     = var.project
  environment = var.environment

  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

  create_uploads_bucket = var.create_uploads_bucket
  uploads_cors_origins  = var.uploads_cors_origins

  tags = var.tags
}

# =============================================================================
# Route 53
# =============================================================================
module "route53" {
  source = "../route53"

  domain_name = var.domain_name
}

# =============================================================================
# ACM (← route53.zone_id)
# =============================================================================
module "acm" {
  source = "../acm"

  project     = var.project
  environment = var.environment

  domain_name               = var.api_domain_name
  subject_alternative_names = var.acm_subject_alternative_names
  zone_id                   = module.route53.zone_id

  tags = var.tags
}

# =============================================================================
# SES (← route53.zone_id)
# =============================================================================
module "ses" {
  source = "../ses"

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name
  zone_id     = module.route53.zone_id

  tags = var.tags
}

# =============================================================================
# ECR
# =============================================================================
module "ecr" {
  source = "../ecr"

  project     = var.project
  environment = var.environment

  image_retention_count = var.ecr_image_retention_count

  additional_repositories = var.ecr_additional_repositories

  tags = var.tags
}

# =============================================================================
# RDS (← vpc.private_subnet_ids, vpc.rds_security_group_id)
# =============================================================================
module "rds" {
  source = "../rds"

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

  tags = var.tags
}

# =============================================================================
# CloudTrail (← s3.cloudtrail_logs_bucket_id)
# =============================================================================
module "cloudtrail" {
  source = "../cloudtrail"

  project     = var.project
  environment = var.environment

  cloudtrail_s3_bucket_id = module.s3.cloudtrail_logs_bucket_id
  log_retention_days      = var.cloudtrail_log_retention_days

  tags = var.tags
}

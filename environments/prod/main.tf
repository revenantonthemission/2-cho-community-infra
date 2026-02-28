###############################################################################
# Prod Environment - Main Configuration
# 모듈을 하나씩 추가하며 인프라를 점진적으로 구축
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

# CloudFront ACM 인증서는 반드시 us-east-1에 생성해야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

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

  single_nat_gateway    = var.single_nat_gateway
  bastion_allowed_cidrs = var.bastion_allowed_cidrs

  tags = local.common_tags
}

# =============================================================================
# Module 2: S3
# =============================================================================
module "s3" {
  source = "../../modules/s3"

  project     = var.project
  environment = var.environment

  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

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
  subject_alternative_names = [var.domain_name]
  zone_id                   = module.route53.zone_id

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

  engine_version         = var.rds_engine_version
  parameter_group_family = var.rds_parameter_group_family
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_max_allocated_storage

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention_days
  deletion_protection   = var.rds_deletion_protection

  tags = local.common_tags
}

# =============================================================================
# Module 6: EFS
# =============================================================================
module "efs" {
  source = "../../modules/efs"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.vpc.private_subnet_ids
  efs_security_group_id = module.vpc.efs_security_group_id

  tags = local.common_tags
}

# =============================================================================
# Module 7: Lambda
# =============================================================================
module "lambda" {
  source = "../../modules/lambda"

  project     = var.project
  environment = var.environment

  private_subnet_ids       = module.vpc.private_subnet_ids
  lambda_security_group_id = module.vpc.lambda_security_group_id

  ecr_image_uri        = "${module.ecr.repository_url}:${var.lambda_image_tag}"
  efs_access_point_arn = module.efs.access_point_arn
  efs_file_system_arn  = module.efs.file_system_arn

  db_host     = module.rds.address
  db_port     = module.rds.port
  db_username = var.db_username
  db_password = var.db_password
  db_name     = var.db_name
  secret_key  = var.secret_key

  cors_allowed_origins = var.cors_allowed_origins

  memory_size             = var.lambda_memory_size
  timeout                 = var.lambda_timeout
  provisioned_concurrency = var.lambda_provisioned_concurrency
  log_retention_days      = var.lambda_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# Module 8: API Gateway (로그 그룹은 이 모듈 내부에서 생성)
# =============================================================================
module "api_gateway" {
  source = "../../modules/api_gateway"

  project     = var.project
  environment = var.environment

  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name

  cors_allowed_origins = var.cors_allowed_origins
  api_domain_name      = var.api_domain_name
  certificate_arn      = module.acm.certificate_arn
  zone_id              = module.route53.zone_id
  log_retention_days   = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# Module 9: CloudWatch (알람 + 대시보드)
# =============================================================================
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  lambda_function_name = module.lambda.function_name
  rds_instance_id      = module.rds.instance_id
  api_gateway_id       = module.api_gateway.api_id

  log_retention_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# Module 10: EC2 + EIP (Bastion Host)
# =============================================================================
module "ec2" {
  source = "../../modules/ec2"

  project     = var.project
  environment = var.environment

  public_subnet_id          = module.vpc.public_subnet_ids[0]
  bastion_security_group_id = module.vpc.bastion_security_group_id

  instance_type  = var.bastion_instance_type
  ssh_public_key = var.bastion_ssh_public_key

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

  tags = local.common_tags
}

# =============================================================================
# Module 12: ACM (us-east-1 — CloudFront 전용)
# =============================================================================
module "acm_cloudfront" {
  source = "../../modules/acm"

  providers = {
    aws = aws.us_east_1
  }

  project     = var.project
  environment = var.environment

  domain_name               = var.domain_name
  subject_alternative_names = []
  zone_id                   = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 13: CloudFront (프론트엔드 CDN + HTTPS + Clean URL)
# =============================================================================
module "cloudfront" {
  source = "../../modules/cloudfront"

  project     = var.project
  environment = var.environment

  domain_name                    = var.domain_name
  s3_bucket_id                   = module.s3.frontend_bucket_id
  s3_bucket_arn                  = module.s3.frontend_bucket_arn
  s3_bucket_regional_domain_name = module.s3.frontend_bucket_regional_domain_name
  acm_certificate_arn            = module.acm_cloudfront.certificate_arn
  zone_id                        = module.route53.zone_id
  api_domain_name                = var.api_domain_name

  tags = local.common_tags
}

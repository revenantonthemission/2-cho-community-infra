###############################################################################
# Prod Environment - Variable Values
###############################################################################

# General
aws_region  = "ap-northeast-2"
project     = "my-community"
environment = "prod"

# IAM
admin_username       = "admin"
create_deployer_role = true

# VPC (prod: AZ별 NAT Gateway)
vpc_cidr           = "10.2.0.0/16"
az_count           = 2
single_nat_gateway = false

bastion_allowed_cidrs = []

# S3
cors_allowed_origins          = ["https://my-community.shop"]
cloudtrail_log_retention_days = 90

# Route 53 + ACM
domain_name     = "my-community.shop"
api_domain_name = "api.my-community.shop"

# ECR
ecr_image_retention_count = 20

# RDS (prod: 고사양 + Multi-AZ)
rds_instance_class        = "db.t3.medium"
rds_allocated_storage     = 50
rds_max_allocated_storage = 200
rds_multi_az              = true
rds_backup_retention_days = 14
rds_deletion_protection   = true

# DB 자격 증명 (terraform apply 시 -var로 전달 — 절대 커밋 금지)
# db_username = "community_user"
# db_password = "change-me"
# secret_key  = "change-me"
# internal_api_key = "change-me"

# Lambda (prod: 고사양 + Provisioned Concurrency)
# CD 워크플로우(deploy-backend.yml)에서 sha-<commit> 태그로 업데이트
# terraform apply 시 이 값이 아닌 CD에서 설정한 이미지가 사용됨
lambda_image_tag               = "latest"
lambda_memory_size             = 1024
lambda_timeout                 = 30
lambda_provisioned_concurrency = 5
lambda_log_retention_days      = 30

# EC2 (Bastion)
bastion_instance_type = "t4g.micro"

# CloudWatch
cloudwatch_log_retention_days = 30

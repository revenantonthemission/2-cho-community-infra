###############################################################################
# Staging Environment - Variable Values
###############################################################################

# General
aws_region  = "ap-northeast-2"
project     = "my-community"
environment = "staging"

# IAM
admin_username       = "admin-staging"
create_deployer_role = false

# VPC
vpc_cidr           = "10.1.0.0/16"
az_count           = 2
single_nat_gateway = true

bastion_allowed_cidrs = []

# S3
cors_allowed_origins          = ["https://staging.my-community.shop"]
cloudtrail_log_retention_days = 60

# Route 53 + ACM
domain_name     = "my-community.shop"
api_domain_name = "api-staging.my-community.shop"

# ECR
ecr_image_retention_count = 10

# RDS (staging: 중간 사양)
rds_instance_class        = "db.t3.small"
rds_allocated_storage     = 20
rds_max_allocated_storage = 100
rds_multi_az              = false
rds_backup_retention_days = 3
rds_deletion_protection   = false

# DB 자격 증명 (terraform apply 시 -var로 전달)
db_username = "community_user"
db_password = "change-me"
secret_key  = "change-me"
internal_api_key = "change-me"

# Lambda (staging: 중간 사양)
# CD 워크플로우(deploy-backend.yml)에서 sha-<commit> 태그로 업데이트
# terraform apply 시 이 값이 아닌 CD에서 설정한 이미지가 사용됨
lambda_image_tag               = "latest"
lambda_memory_size             = 512
lambda_timeout                 = 30
lambda_provisioned_concurrency = 0
lambda_log_retention_days      = 14

# EC2 (Bastion)
bastion_instance_type = "t4g.micro"

# CloudWatch
cloudwatch_log_retention_days = 14

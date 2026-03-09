###############################################################################
# Dev Environment - Variable Values (Free Tier 최적화)
###############################################################################

# General
aws_region  = "ap-northeast-2"
project     = "my-community"
environment = "dev"

# IAM
admin_username       = "admin-dev"
create_deployer_role = false

# VPC
vpc_cidr           = "10.0.0.0/16"
az_count           = 2
single_nat_gateway = true # dev: NAT GW 1개 (~$32/month 고정 비용 주의)

# Bastion SSH 허용 IP (본인 IP로 변경 필요)
# 예: bastion_allowed_cidrs = ["203.0.113.0/32"]
bastion_allowed_cidrs = []  # -var 플래그 또는 secret.tfvars로 설정

# S3
# allow_credentials=true 시 와일드카드 불가
cors_allowed_origins          = ["https://my-community.shop", "http://my-community-dev-frontend.s3-website.ap-northeast-2.amazonaws.com"]
cloudtrail_log_retention_days = 30

# Route 53 + ACM
domain_name     = "my-community.shop"
api_domain_name = "api.my-community.shop"

# ECR (Free Tier: 500MB)
ecr_image_retention_count = 3

# RDS (Free Tier: db.t3.micro, 750시간/월, 20GB)
rds_instance_class        = "db.t3.micro"
rds_allocated_storage     = 20
rds_max_allocated_storage = 20    # Free Tier 내 유지
rds_multi_az              = false # Free Tier는 Single-AZ만
rds_backup_retention_days = 1     # 최소
rds_deletion_protection   = false

# DB 자격 증명 (terraform apply 시 -var로 전달 권장)
# db_username = "community_user"
# db_password = "change-me"
# secret_key  = "change-me"
# internal_api_key = "change-me"

# Lambda (Free Tier: 1M 요청, 400K GB-초)
# CD 워크플로우(deploy-backend.yml)에서 sha-<commit> 태그로 업데이트
# terraform apply 시 이 값이 아닌 CD에서 설정한 이미지가 사용됨
lambda_image_tag               = "latest"
lambda_memory_size             = 256 # 최소로 유지하여 GB-초 절약
lambda_timeout                 = 30
lambda_provisioned_concurrency = 0 # Provisioned Concurrency는 항상 과금
lambda_log_retention_days      = 7

# EC2 (Free Tier: t2.micro 또는 t3.micro, 750시간/월)
bastion_instance_type  = "t3.micro" # t4g는 Free Tier 아님!
bastion_ssh_public_key = ""  # -var 플래그 또는 secret.tfvars로 설정

# CloudWatch (Free Tier: 10 알람, 5GB 로그)
cloudwatch_log_retention_days = 7

###############################################################################
# Dev Environment - Variable Values
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

# S3
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

# DB 자격 증명 (terraform apply 시 -var 또는 secret.tfvars로 전달)
db_username = "manager_dev"
# db_password는 secret.tfvars로 전달

# K8s 클러스터
create_k8s_cluster = true
# k8s_allowed_ssh_cidrs: secret.tfvars에서 관리

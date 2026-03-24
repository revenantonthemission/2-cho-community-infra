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

# S3 / CloudTrail
cloudtrail_log_retention_days = 60

# Route 53 + ACM
domain_name     = "my-community.shop"
api_domain_name = "api-staging.my-community.shop"

# ECR
ecr_image_retention_count = 10

# RDS (staging: 중간 사양)
rds_engine_version        = "8.0"
rds_instance_class        = "db.t3.micro"
rds_allocated_storage     = 20
rds_max_allocated_storage = 100
rds_multi_az              = false
rds_backup_retention_days = 1
rds_deletion_protection   = false

# DB 자격 증명 (terraform apply 시 -var 또는 secret.tfvars로 전달)
db_name     = "community_service"
db_username = "admin"
# db_password → secret.tfvars

# K8s 클러스터
create_k8s_cluster = true
# k8s_ssh_key_name, k8s_allowed_ssh_cidrs → secret.tfvars

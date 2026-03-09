###############################################################################
# Staging Environment - Variables
###############################################################################

# =============================================================================
# General
# =============================================================================
variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

# =============================================================================
# IAM
# =============================================================================
variable "admin_username" {
  description = "관리자 IAM 사용자 이름"
  type        = string
  default     = ""
}

variable "create_deployer_role" {
  description = "Terraform 배포용 IAM 역할 생성 여부"
  type        = bool
  default     = false
}

# =============================================================================
# VPC
# =============================================================================
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}

variable "az_count" {
  description = "가용 영역 수"
  type        = number
}

variable "single_nat_gateway" {
  description = "NAT Gateway 단일 사용 여부"
  type        = bool
}

variable "bastion_allowed_cidrs" {
  description = "Bastion SSH 허용 CIDR 목록"
  type        = list(string)
  default     = []
}

# =============================================================================
# S3
# =============================================================================
variable "cors_allowed_origins" {
  description = "CORS 허용 오리진 목록"
  type        = list(string)
  default     = ["*"]
}

variable "cloudtrail_log_retention_days" {
  description = "CloudTrail 로그 보존 일수"
  type        = number
  default     = 90
}

# =============================================================================
# Route 53 + ACM
# =============================================================================
variable "domain_name" {
  description = "기본 도메인 이름"
  type        = string
}

variable "api_domain_name" {
  description = "API 서브도메인"
  type        = string
}

# =============================================================================
# ECR
# =============================================================================
variable "ecr_image_retention_count" {
  description = "ECR 이미지 보존 수"
  type        = number
  default     = 10
}

# =============================================================================
# RDS
# =============================================================================
variable "rds_engine_version" {
  description = "MySQL 엔진 버전"
  type        = string
  default     = "8.0"
}

variable "rds_instance_class" {
  description = "DB 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "초기 스토리지 (GB)"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "최대 자동 확장 스토리지 (GB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "DB 이름"
  type        = string
  default     = "community_service"
}

variable "db_username" {
  description = "DB 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "DB 비밀번호"
  type        = string
  sensitive   = true

  validation {
    condition     = var.db_password != "change-me" && length(var.db_password) >= 8
    error_message = "db_password는 'change-me'가 아닌 8자 이상의 실제 비밀번호를 -var 또는 secret.tfvars로 전달해야 합니다."
  }
}

variable "rds_multi_az" {
  description = "Multi-AZ 배포"
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "백업 보존 일수"
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "삭제 보호"
  type        = bool
  default     = false
}

# =============================================================================
# Lambda
# =============================================================================
variable "lambda_image_tag" {
  description = "Lambda ECR 이미지 태그"
  type        = string
  default     = "latest"
}

variable "secret_key" {
  description = "JWT SECRET_KEY"
  type        = string
  sensitive   = true

  validation {
    condition     = var.secret_key != "change-me" && length(var.secret_key) > 0
    error_message = "secret_key는 'change-me'가 아닌 실제 키를 -var 또는 secret.tfvars로 전달해야 합니다."
  }
}

variable "internal_api_key" {
  description = "내부 API 인증 키 (EventBridge 배치 작업 호출용). 빈 값이면 EventBridge 모듈 비활성화"
  type        = string
  sensitive   = true
  default     = ""
}

variable "lambda_memory_size" {
  description = "Lambda 메모리 (MB)"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda 타임아웃 (초)"
  type        = number
  default     = 30
}

variable "lambda_provisioned_concurrency" {
  description = "Provisioned Concurrency 수"
  type        = number
  default     = 0
}

variable "lambda_log_retention_days" {
  description = "Lambda 로그 보존 일수"
  type        = number
  default     = 14
}


# =============================================================================
# EC2 (Bastion)
# =============================================================================
variable "bastion_instance_type" {
  description = "Bastion 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_public_key" {
  description = "Bastion SSH 공개키"
  type        = string
  default     = ""
}

# =============================================================================
# CloudWatch
# =============================================================================
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch 로그 보존 일수"
  type        = number
  default     = 14
}

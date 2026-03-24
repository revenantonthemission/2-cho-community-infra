###############################################################################
# Prod Environment - Variables
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

# =============================================================================
# S3
# =============================================================================
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
# EKS Cluster
# =============================================================================
variable "create_eks_cluster" {
  description = "EKS 클러스터 생성 여부"
  type        = bool
  default     = true
}

variable "eks_cluster_version" {
  description = "EKS 클러스터 버전"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_types" {
  description = "EKS 노드 인스턴스 타입"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "EKS 노드 그룹 원하는 노드 수"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "EKS 노드 그룹 최소 노드 수"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "EKS 노드 그룹 최대 노드 수"
  type        = number
  default     = 4
}

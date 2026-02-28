###############################################################################
# RDS Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "RDS 보안 그룹 ID"
  type        = string
}

variable "engine_version" {
  description = "MySQL 엔진 버전"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "DB 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "초기 스토리지 (GB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "최대 자동 확장 스토리지 (GB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "community_service"
}

variable "db_username" {
  description = "마스터 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "마스터 비밀번호"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Multi-AZ 배포 여부"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "자동 백업 보존 일수"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "삭제 보호 활성화 여부"
  type        = bool
  default     = false
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}

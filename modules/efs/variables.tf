# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
###############################################################################
# EFS Module - Variables
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
  description = "프라이빗 서브넷 ID 목록 (마운트 타겟용)"
  type        = list(string)
}

variable "efs_security_group_id" {
  description = "EFS 보안 그룹 ID"
  type        = string
}

variable "performance_mode" {
  description = "EFS 성능 모드 (generalPurpose 또는 maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "throughput_mode" {
  description = "EFS 처리량 모드 (bursting 또는 elastic)"
  type        = string
  default     = "bursting"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
